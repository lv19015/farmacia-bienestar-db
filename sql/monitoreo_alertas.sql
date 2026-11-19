---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Monitoreo y alertas
-- EJECUTAR DESPUES DE seguridad.sql, conectado como postgres.
--
-- Que hace:
--   1. Tabla umbral_alerta: cada metrica vigilada con su umbral y severidad
--      (se pueden cambiar con un UPDATE, sin tocar el codigo)
--   2. Tabla alerta: historial de alertas generadas y si ya fueron atendidas
--   3. Funcion fn_verificar_alertas(): mide las metricas, compara con los
--      umbrales, registra las alertas y las devuelve
--   4. Permisos: monitoreo la ejecuta; auditor y administrador la consultan
--
-- Se ejecuta a mano con  SELECT * FROM fn_verificar_alertas();  o de forma
-- programada con monitoreo_programado.ps1 (Programador de tareas de Windows).
-- Una alerta se dispara cuando el valor medido es MAYOR que el umbral.
--
-- El espacio en disco y el estado de vacuum/analyze se miden aqui con
-- umbrales; las consultas de detalle estan en mantenimiento.sql (seccion 4).
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 1. UMBRALES
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE TABLE IF NOT EXISTS umbral_alerta (
    metrica      VARCHAR(40)  PRIMARY KEY,
    descripcion  TEXT         NOT NULL,
    umbral       NUMERIC      NOT NULL CHECK (umbral >= 0),
    unidad       VARCHAR(20)  NOT NULL,
    severidad    VARCHAR(10)  NOT NULL CHECK (severidad IN ('BAJA', 'MEDIA', 'ALTA')),
    activa       BOOLEAN      NOT NULL DEFAULT TRUE
);

INSERT INTO umbral_alerta (metrica, descripcion, umbral, unidad, severidad) VALUES
 -- Seguridad
 ('superusuarios_extra',          'Roles superusuario distintos de postgres',                        0,    'roles',     'ALTA'),
 ('passwords_md5',                'Usuarios con contrasena guardada con md5 (debil)',                 0,    'usuarios',  'ALTA'),
 ('cambios_por_superusuario_24h', 'Cambios de datos hechos por postgres en las ultimas 24 h',          0,    'cambios',   'MEDIA'),
 ('borrados_1h',                  'Borrados (DELETE) registrados en la bitacora en la ultima hora',   10,   'borrados',  'ALTA'),
 ('conexiones_pct',               'Conexiones abiertas respecto a max_connections',                   80,   '%',         'MEDIA'),
 -- Disco y mantenimiento
 ('tamano_base_mb',               'Tamano total de la base de datos',                                 1024, 'MB',        'MEDIA'),
 ('tamano_ts_bitacora_mb',        'Tamano del tablespace de la bitacora',                             512,  'MB',        'MEDIA'),
 ('filas_muertas_pct',            'Mayor porcentaje de filas muertas en una tabla (min. 100 filas)',  20,   '%',         'MEDIA'),
 -- Negocio
 ('lotes_vencidos_con_stock',     'Lotes vencidos que aun tienen existencias',                        0,    'lotes',     'ALTA'),
 ('lotes_por_vencer_60d',         'Lotes con existencias que vencen en los proximos 60 dias',         0,    'lotes',     'MEDIA'),
 ('productos_stock_bajo',         'Productos con menos de 20 unidades en total',                      0,    'productos', 'MEDIA'),
 ('dte_sin_aceptar',              'Facturas electronicas pendientes o rechazadas con mas de 1 dia',   0,    'facturas',  'MEDIA')
ON CONFLICT (metrica) DO NOTHING;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 2. HISTORIAL DE ALERTAS
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE TABLE IF NOT EXISTS alerta (
    id_alerta       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_hora      TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp(),
    metrica         VARCHAR(40)  NOT NULL REFERENCES umbral_alerta (metrica),
    severidad       VARCHAR(10)  NOT NULL,
    valor           NUMERIC      NOT NULL,
    umbral          NUMERIC      NOT NULL,
    detalle         TEXT,
    atendida        BOOLEAN      NOT NULL DEFAULT FALSE,
    fecha_atencion  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_alerta_abiertas
    ON alerta (fecha_hora DESC) TABLESPACE ts_indices
    WHERE NOT atendida;

CREATE OR REPLACE VIEW v_alertas_abiertas AS
SELECT id_alerta, fecha_hora, severidad, metrica, valor, umbral, detalle
  FROM alerta
 WHERE NOT atendida
 ORDER BY CASE severidad WHEN 'ALTA' THEN 1 WHEN 'MEDIA' THEN 2 ELSE 3 END,
          fecha_hora DESC;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 3. FUNCION QUE VERIFICA LAS METRICAS
-- Se ejecuta como su propietario (SECURITY DEFINER) para poder leer las
-- estadisticas y las tablas sin dar esos permisos al rol de monitoreo.
-- Si ya hay una alerta abierta de la misma metrica en la ultima hora no se
-- duplica, pero igual se devuelve para que quede en el log.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE OR REPLACE FUNCTION fn_verificar_alertas()
RETURNS TABLE (metrica_alerta  TEXT,
               severidad_alerta TEXT,
               valor_actual    NUMERIC,
               umbral_definido NUMERIC,
               detalle_alerta  TEXT)
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    m         RECORD;
    v_valor   NUMERIC;
    v_detalle TEXT;
BEGIN
    FOR m IN SELECT * FROM umbral_alerta WHERE activa ORDER BY metrica LOOP
        v_valor   := NULL;
        v_detalle := NULL;

        CASE m.metrica
            WHEN 'superusuarios_extra' THEN
                SELECT count(*), string_agg(rolname, ', ')
                  INTO v_valor, v_detalle
                  FROM pg_roles WHERE rolsuper AND rolname <> 'postgres';

            WHEN 'passwords_md5' THEN
                SELECT count(*), string_agg(rolname, ', ')
                  INTO v_valor, v_detalle
                  FROM pg_authid WHERE rolpassword LIKE 'md5%';

            WHEN 'cambios_por_superusuario_24h' THEN
                SELECT count(*), 'Tablas: ' || string_agg(DISTINCT tabla_afectada, ', ')
                  INTO v_valor, v_detalle
                  FROM bitacora
                 WHERE usuario = 'postgres'
                   AND fecha_hora > now() - INTERVAL '24 hours';

            WHEN 'borrados_1h' THEN
                SELECT count(*), 'Tablas: ' || string_agg(DISTINCT tabla_afectada, ', ')
                  INTO v_valor, v_detalle
                  FROM bitacora
                 WHERE operacion = 'DELETE'
                   AND fecha_hora > now() - INTERVAL '1 hour';

            WHEN 'conexiones_pct' THEN
                SELECT round(100.0 * count(*) / current_setting('max_connections')::int, 1)
                  INTO v_valor
                  FROM pg_stat_activity WHERE backend_type = 'client backend';
                v_detalle := v_valor || '% de max_connections en uso';

            WHEN 'tamano_base_mb' THEN
                v_valor   := round(pg_database_size(current_database()) / 1048576.0, 1);
                v_detalle := 'La base ocupa ' || v_valor || ' MB';

            WHEN 'tamano_ts_bitacora_mb' THEN
                IF EXISTS (SELECT 1 FROM pg_tablespace WHERE spcname = 'ts_bitacora') THEN
                    v_valor   := round(pg_tablespace_size('ts_bitacora') / 1048576.0, 1);
                    v_detalle := 'ts_bitacora ocupa ' || v_valor || ' MB';
                END IF;

            WHEN 'filas_muertas_pct' THEN
                SELECT round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1),
                       'Tabla ' || relname
                  INTO v_valor, v_detalle
                  FROM pg_stat_user_tables
                 WHERE n_live_tup + n_dead_tup >= 100
                 ORDER BY n_dead_tup::numeric / (n_live_tup + n_dead_tup) DESC
                 LIMIT 1;

            WHEN 'lotes_vencidos_con_stock' THEN
                SELECT count(*), left(string_agg(p.nombre || ' lote ' || l.numero_lote
                                      || ' (stock ' || l.stock_actual || ')', '; '), 300)
                  INTO v_valor, v_detalle
                  FROM lote l JOIN producto p ON p.id_producto = l.id_producto
                 WHERE l.fecha_caducidad < CURRENT_DATE AND l.stock_actual > 0;

            WHEN 'lotes_por_vencer_60d' THEN
                SELECT count(*), left(string_agg(p.nombre || ' lote ' || l.numero_lote
                                      || ' vence ' || l.fecha_caducidad, '; '), 300)
                  INTO v_valor, v_detalle
                  FROM lote l JOIN producto p ON p.id_producto = l.id_producto
                 WHERE l.stock_actual > 0
                   AND l.fecha_caducidad BETWEEN CURRENT_DATE AND CURRENT_DATE + 60;

            WHEN 'productos_stock_bajo' THEN
                SELECT count(*), left(string_agg(nombre || ' (' || stock || ')', '; '), 300)
                  INTO v_valor, v_detalle
                  FROM (SELECT p.nombre, COALESCE(SUM(l.stock_actual), 0) AS stock
                          FROM producto p
                          LEFT JOIN lote l ON l.id_producto = p.id_producto
                         GROUP BY p.id_producto, p.nombre
                        HAVING COALESCE(SUM(l.stock_actual), 0) < 20) s;

            WHEN 'dte_sin_aceptar' THEN
                SELECT count(*), left(string_agg('venta ' || id_venta || ' ' || estado_envio, '; '), 300)
                  INTO v_valor, v_detalle
                  FROM factura_dte
                 WHERE estado_envio IN ('PENDIENTE', 'RECHAZADO')
                   AND fecha_emision < now() - INTERVAL '1 day';

            ELSE
                NULL;   -- metrica sin calculo definido: se ignora
        END CASE;

        IF v_valor IS NOT NULL AND v_valor > m.umbral THEN
            IF NOT EXISTS (SELECT 1 FROM alerta a
                            WHERE a.metrica = m.metrica AND NOT a.atendida
                              AND a.fecha_hora > now() - INTERVAL '1 hour') THEN
                INSERT INTO alerta (metrica, severidad, valor, umbral, detalle)
                VALUES (m.metrica, m.severidad, v_valor, m.umbral, v_detalle);
            END IF;
            metrica_alerta   := m.metrica;
            severidad_alerta := m.severidad;
            valor_actual     := v_valor;
            umbral_definido  := m.umbral;
            detalle_alerta   := v_detalle;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_verificar_alertas() IS
    'Mide las metricas de umbral_alerta, registra las alertas en la tabla alerta y devuelve las que superan su umbral.';

-- Marcar una alerta como atendida
CREATE OR REPLACE FUNCTION fn_atender_alerta(p_id_alerta BIGINT)
RETURNS VOID
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    UPDATE alerta SET atendida = TRUE, fecha_atencion = now()
     WHERE id_alerta = p_id_alerta AND NOT atendida;
$$ LANGUAGE sql;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 4. PERMISOS
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
REVOKE ALL ON umbral_alerta, alerta, v_alertas_abiertas FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_verificar_alertas()    FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atender_alerta(BIGINT) FROM PUBLIC;

GRANT SELECT ON umbral_alerta, alerta, v_alertas_abiertas
   TO rol_monitoreo, rol_auditor, rol_admin_farmacia;
GRANT UPDATE (umbral, severidad, activa) ON umbral_alerta TO rol_admin_farmacia;
GRANT EXECUTE ON FUNCTION fn_verificar_alertas()    TO rol_monitoreo, rol_admin_farmacia;
GRANT EXECUTE ON FUNCTION fn_atender_alerta(BIGINT) TO rol_admin_farmacia;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 5. COMPROBACIONES 
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

-- 5.1 Umbrales definidos
SELECT metrica, umbral, unidad, severidad, descripcion FROM umbral_alerta ORDER BY severidad, metrica;

-- 5.2 Ejecutar la verificacion: devuelve las alertas que superan su umbral
SELECT * FROM fn_verificar_alertas();

-- 5.3 Alertas registradas, ordenadas por severidad
SELECT * FROM v_alertas_abiertas;

-- 5.4 Probar que el rol de monitoreo puede ejecutarla pero no leer los datos
SET ROLE usr_monitor;
SELECT metrica_alerta, severidad_alerta, valor_actual FROM fn_verificar_alertas();
-- SELECT * FROM venta;   -- debe dar: permission denied for table venta
RESET ROLE;

-- 5.5 Demostracion de que una alerta se dispara al superar un umbral:
--     se baja el umbral de conexiones a 0 para forzarla y luego se restaura.
UPDATE umbral_alerta SET umbral = 0 WHERE metrica = 'conexiones_pct';
SELECT metrica_alerta, severidad_alerta, valor_actual, umbral_definido, detalle_alerta
  FROM fn_verificar_alertas() WHERE metrica_alerta = 'conexiones_pct';
UPDATE umbral_alerta SET umbral = 80 WHERE metrica = 'conexiones_pct';

-- 5.6 Atender una alerta (la saca de la lista de abiertas)
-- SELECT fn_atender_alerta(1);
