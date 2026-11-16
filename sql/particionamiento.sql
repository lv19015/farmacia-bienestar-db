---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Particionamiento de la bitacora
-- EJECUTAR DESPUES DE indices_bitacora.sql
--
-- Que hace:
--   1. Convierte la tabla bitacora en una tabla particionada por rango mensual sobre fecha_hora, conservando los datos existentes
--   2. Crea las particiones (en el tablespace ts_bitacora), una particion DEFAULT y una funcion para crear particiones futuras
--   3. Define la politica de retencion: separar (DETACH) y archivar las particiones antiguas
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 1. MIGRACION DE LA TABLA bitacora A TABLA PARTICIONADA
-- Todo va en una transaccion y si algo falla, no se pierde la bitacora
-- ---------------------------------------------------------------------
BEGIN;

-- Bloquea escrituras mientras se hace el cambio
LOCK TABLE bitacora IN ACCESS EXCLUSIVE MODE;

-- Se renombra la tabla vieja y sus objetos para liberar los nombres
ALTER TABLE bitacora RENAME TO bitacora_old;
ALTER INDEX bitacora_pkey          RENAME TO bitacora_old_pkey;
ALTER INDEX idx_bitacora_usuario   RENAME TO idx_bitacora_old_usuario;
ALTER TABLE bitacora_old RENAME CONSTRAINT bitacora_operacion_check
                                        TO bitacora_old_operacion_check;

-- Nueva tabla particionada.
-- La PK debe incluir la columna de particion (fecha_hora).
CREATE TABLE bitacora (
    id_bitacora      BIGINT GENERATED ALWAYS AS IDENTITY,
    tabla_afectada   VARCHAR(60)  NOT NULL,
    operacion        VARCHAR(10)  NOT NULL
                     CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    usuario          VARCHAR(60)  NOT NULL,
    nro_transaccion  TEXT         NOT NULL,
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    fecha_hora       TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (id_bitacora, fecha_hora)
) PARTITION BY RANGE (fecha_hora);

COMMENT ON TABLE bitacora IS
    'Bitacora automatica de cambios (particionada por mes sobre fecha_hora): usuario, operacion y valores antes/despues (JSONB).';

-- Particion DEFAULT: recibe cualquier fila que no caiga en una particion mensual, asi nunca falla un INSERT de auditoria (y se bloquearia la venta).
CREATE TABLE bitacora_default PARTITION OF bitacora DEFAULT
    TABLESPACE ts_bitacora;

-- Particiones mensuales: desde el mes mas antiguo de los datos existentes (o el mes actual si la bitacora estaba vacia) hasta 3 meses adelante.
DO $$
DECLARE
    v_desde DATE;
    v_mes   DATE;
BEGIN
    SELECT date_trunc('month', COALESCE(min(fecha_hora), now()))::date
      INTO v_desde
      FROM bitacora_old;

    v_mes := v_desde;
    WHILE v_mes <= (date_trunc('month', now()) + INTERVAL '3 months')::date LOOP
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF bitacora
             FOR VALUES FROM (%L) TO (%L) TABLESPACE ts_bitacora',
            'bitacora_' || to_char(v_mes, 'YYYY_MM'),
            v_mes,
            (v_mes + INTERVAL '1 month')::date);
        v_mes := (v_mes + INTERVAL '1 month')::date;
    END LOOP;
END $$;

-- Se copian los datos conservando los id originales
INSERT INTO bitacora (id_bitacora, tabla_afectada, operacion, usuario,
                      nro_transaccion, datos_anteriores, datos_nuevos,
                      fecha_hora)
OVERRIDING SYSTEM VALUE
SELECT id_bitacora, tabla_afectada, operacion, usuario,
       nro_transaccion, datos_anteriores, datos_nuevos, fecha_hora
  FROM bitacora_old;

-- El identity de la tabla nueva continua despues del ultimo id copiado
SELECT setval(pg_get_serial_sequence('bitacora', 'id_bitacora'),
              COALESCE((SELECT max(id_bitacora) FROM bitacora_old), 0) + 1,
              false);

DROP TABLE bitacora_old;

-- Los indices se crean en la tabla padre y PostgreSQL los replica en cada particion (tambien en las futuras). Van en ts_indices.
CREATE INDEX idx_bitacora_usuario
    ON bitacora USING hash (usuario) TABLESPACE ts_indices;
CREATE INDEX idx_bitacora_tabla_fecha
    ON bitacora (tabla_afectada, fecha_hora) TABLESPACE ts_indices;

COMMIT;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 2. FUNCION PARA CREAR PARTICIONES FUTURAS
-- Se ejecuta manualmente o desde la tarea de mantenimiento.
CREATE OR REPLACE FUNCTION fn_crear_particiones_bitacora(p_meses INTEGER DEFAULT 3)
RETURNS SETOF TEXT AS $$
DECLARE
    v_mes    DATE := date_trunc('month', now())::date;
    v_limite DATE := (date_trunc('month', now()) + make_interval(months => p_meses))::date;
    v_nombre TEXT;
BEGIN
    WHILE v_mes <= v_limite LOOP
        v_nombre := 'bitacora_' || to_char(v_mes, 'YYYY_MM');
        IF to_regclass(v_nombre) IS NULL THEN
            EXECUTE format(
                'CREATE TABLE %I PARTITION OF bitacora
                 FOR VALUES FROM (%L) TO (%L) TABLESPACE ts_bitacora',
                v_nombre, v_mes, (v_mes + INTERVAL '1 month')::date);
            RETURN NEXT v_nombre;
        END IF;
        v_mes := (v_mes + INTERVAL '1 month')::date;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_crear_particiones_bitacora(INTEGER) IS
    'Crea las particiones mensuales de bitacora para los proximos N meses (por defecto 3).';


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 3. POLITICA DE RETENCION
CREATE OR REPLACE FUNCTION fn_archivar_particiones_bitacora(p_meses_retencion INTEGER DEFAULT 12)
RETURNS SETOF TEXT AS $$
DECLARE
    r        RECORD;
    v_corte  DATE := (date_trunc('month', now()) - make_interval(months => p_meses_retencion))::date;
    v_mes    DATE;
    v_nuevo  TEXT;
BEGIN
    FOR r IN
        SELECT c.relname
          FROM pg_inherits i
          JOIN pg_class c ON c.oid = i.inhrelid
         WHERE i.inhparent = 'bitacora'::regclass
           AND c.relname ~ '^bitacora_[0-9]{4}_[0-9]{2}$'
         ORDER BY c.relname
    LOOP
        v_mes := to_date(substr(r.relname, 10), 'YYYY_MM');
        IF v_mes < v_corte THEN
            v_nuevo := 'arch_' || r.relname;
            EXECUTE format('ALTER TABLE bitacora DETACH PARTITION %I', r.relname);
            EXECUTE format('ALTER TABLE %I RENAME TO %I', r.relname, v_nuevo);
            RETURN NEXT v_nuevo;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_archivar_particiones_bitacora(INTEGER) IS
    'Separa de bitacora las particiones mas antiguas que N meses (por defecto 12) y las renombra arch_*. Exportarlas con pg_dump antes de eliminarlas.';

-- Ejemplo para eliminar una particion ya exportada:
--   DROP TABLE arch_bitacora_2025_01;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 4. COMPROBACIONES
-- Particiones de bitacora con su tamano y cantidad de filas:
SELECT c.relname                               AS particion,
       pg_get_expr(c.relpartbound, c.oid)      AS rango,
       COALESCE(t.spcname, 'pg_default')       AS tablespace,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano,
       c.reltuples::bigint                     AS filas_aprox
  FROM pg_inherits i
  JOIN pg_class c      ON c.oid = i.inhrelid
  LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
 WHERE i.inhparent = 'bitacora'::regclass
 ORDER BY c.relname;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- EJEMPLO
-- Verificar que una consulta por fecha solo lee la particion necesaria
-- (en el plan debe aparecer unicamente la particion del mes consultado):
-- EXPLAIN SELECT * FROM bitacora
--  WHERE fecha_hora >= date_trunc('month', now())
--    AND fecha_hora <  date_trunc('month', now()) + INTERVAL '1 month';
