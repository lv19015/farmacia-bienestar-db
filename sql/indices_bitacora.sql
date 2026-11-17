-- =====================================================================
-- Farmacia Comunitaria "Bienestar" - Auditoria e indices
-- Ejecutar DESPUES de generar toda la estructura de la base de datos
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABLESPACES
-- IMPORTANTE: las carpetas deben existir antes, estar vacias y pertenecer
-- al usuario del sistema operativo que corre PostgreSQL (normalmente "postgres"). 
-- Ajustar las rutas segun la ubicacion de las carpetas de cada integrante
-- Ejecutar la creacion de cada TABLESPACE por separado antes de ejecutar todo el script
-- ---------------------------------------------------------------------
CREATE TABLESPACE ts_bitacora LOCATION 'C:/pgdata/ts_bitacora';
CREATE TABLESPACE ts_indices  LOCATION 'C:/pgdata/ts_indices';

-- ---------------------------------------------------------------------
-- BITACORA DE AUDITORIA
-- Guarda quien hizo cada INSERT/UPDATE/DELETE y como estaba el registro
-- antes y despues (JSONB). Es una tabla de solo agregar, por eso usa fecha_hora
-- ---------------------------------------------------------------------
CREATE TABLE bitacora (
    id_bitacora      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla_afectada   VARCHAR(60)  NOT NULL,
    operacion        VARCHAR(10)  NOT NULL
                     CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    usuario          VARCHAR(60)  NOT NULL,
    nro_transaccion  TEXT         NOT NULL,
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    fecha_hora       TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp()
) TABLESPACE ts_bitacora;

COMMENT ON TABLE bitacora IS
    'Bitacora automatica de cambios: usuario, operacion y valores antes/despues (JSONB).';

-- ---------------------------------------------------------------------
-- FUNCION GENERICA DE AUDITORIA
-- Una sola funcion para todas las tablas (usa TG_OP, TG_TABLE_NAME, OLD y NEW).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditoria_generica()
RETURNS trigger AS $$
BEGIN
    INSERT INTO bitacora (
        tabla_afectada, operacion, usuario, nro_transaccion,
        datos_anteriores, datos_nuevos, fecha_hora
    ) VALUES (
        TG_TABLE_NAME,
        TG_OP,
        current_user,
        pg_current_xact_id()::text,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END,
        clock_timestamp()
    );
    RETURN NULL;  -- en triggers AFTER el valor de retorno se ignora
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- TRIGGERS DE AUDITORIA en las tablas criticas
-- Para auditar otra tabla solo hay que agregar el nombre a la lista.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['venta', 'lote', 'compra', 'producto',
                             'paciente', 'receta']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_audit_%s
             AFTER INSERT OR UPDATE OR DELETE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_auditoria_generica()',
            t, t);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- INDICES
-- Mover al tablespace de indices, los indices creados en el primer
-- script de la estructura de la db (B-tree sobre llaves foraneas, fechas y caducidad).
-- ---------------------------------------------------------------------
ALTER INDEX idx_compra_proveedor         SET TABLESPACE ts_indices;
ALTER INDEX idx_lote_producto            SET TABLESPACE ts_indices;
ALTER INDEX idx_lote_compra              SET TABLESPACE ts_indices;
ALTER INDEX idx_lote_caducidad           SET TABLESPACE ts_indices;
ALTER INDEX idx_receta_paciente          SET TABLESPACE ts_indices;
ALTER INDEX idx_venta_cliente            SET TABLESPACE ts_indices;
ALTER INDEX idx_venta_receta             SET TABLESPACE ts_indices;
ALTER INDEX idx_venta_fecha              SET TABLESPACE ts_indices;
ALTER INDEX idx_detalle_venta_lote       SET TABLESPACE ts_indices;
ALTER INDEX idx_venta_promocion_promo    SET TABLESPACE ts_indices;
ALTER INDEX idx_historial_puntos_cliente SET TABLESPACE ts_indices;
ALTER INDEX idx_promocion_vigencia       SET TABLESPACE ts_indices;
ALTER INDEX idx_detalle_compra_producto  SET TABLESPACE ts_indices;

-- HASH: busquedas de igualdad exacta (=)
-- Bitacora por usuario, y lote por su codigo (el UNIQUE compuesto de
-- lote empieza por id_producto, asi que no funciona para buscar solo por numero_lote).
CREATE INDEX idx_bitacora_usuario
    ON bitacora USING hash (usuario) TABLESPACE ts_indices;
CREATE INDEX idx_lote_numero_hash
    ON lote USING hash (numero_lote) TABLESPACE ts_indices;

-- UNICO POR EXPRESION (LOWER): unicidad sin distinguir mayusculas
-- Evita correos duplicados escritos distinto
CREATE UNIQUE INDEX idx_cliente_correo_unico
    ON cliente (LOWER(correo)) TABLESPACE ts_indices;

-- GIN POR TRIGRAMAS (pg_trgm): busquedas parciales o con errores de digitacion (LIKE '%texto%' y operador de similitud %).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_producto_nombre_trgm
    ON producto USING gin (nombre gin_trgm_ops) TABLESPACE ts_indices;
CREATE INDEX idx_cliente_nombre_trgm
    ON cliente USING gin (nombre gin_trgm_ops) TABLESPACE ts_indices;