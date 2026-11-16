---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Mantenimiento y monitoreo
-- EJECUTAR DESPUES DE particionamiento.sql

-- Nota: este script se ejecuta con psql o desde la herramienta Query Tool
-- de pgAdmin 4. 
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 1. AUTOVACUUM POR TABLA
-- Se ajusta con parametros de almacenamiento de cada tabla.
ALTER TABLE lote SET (
    autovacuum_vacuum_scale_factor  = 0.05,  -- vacuum al 5 % de filas muertas
    autovacuum_analyze_scale_factor = 0.02
);
ALTER TABLE venta SET (
    autovacuum_vacuum_scale_factor  = 0.05,
    autovacuum_analyze_scale_factor = 0.02
);
ALTER TABLE detalle_venta SET (
    autovacuum_vacuum_scale_factor  = 0.05,
    autovacuum_analyze_scale_factor = 0.02
);
ALTER TABLE cliente SET (
    autovacuum_vacuum_scale_factor  = 0.10,  -- puntos acumulados cambian seguido
    autovacuum_analyze_scale_factor = 0.05
);
ALTER TABLE historial_puntos SET (
    autovacuum_vacuum_scale_factor  = 0.10,
    autovacuum_analyze_scale_factor = 0.05
);

-- Comprobar los parametros aplicados:
SELECT relname, reloptions
  FROM pg_class
 WHERE relname IN ('lote', 'venta', 'detalle_venta', 'cliente', 'historial_puntos');


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 2. MANTENIMIENTO MENSUAL DE LA BITACORA
-- Se programa con el Programador de tareas de Windows o se ejecuta a mano:  SELECT * FROM fn_mantenimiento_mensual();
CREATE OR REPLACE FUNCTION fn_mantenimiento_mensual(
    p_meses_adelante  INTEGER DEFAULT 3,
    p_meses_retencion INTEGER DEFAULT 12)
RETURNS TABLE (accion TEXT, particion TEXT) AS $$
BEGIN
    RETURN QUERY
        SELECT 'CREADA'::text, p FROM fn_crear_particiones_bitacora(p_meses_adelante) AS p;
    RETURN QUERY
        SELECT 'ARCHIVADA'::text, p FROM fn_archivar_particiones_bitacora(p_meses_retencion) AS p;
END;
$$ LANGUAGE plpgsql;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 3. MANTENIMIENTO MANUAL
-- VACUUM libera espacio muerto y ANALYZE actualiza las estadisticas que usa el planificador. VERBOSE muestra el detalle (util como evidencia).
VACUUM (ANALYZE, VERBOSE) lote;
VACUUM (ANALYZE) venta;
VACUUM (ANALYZE) detalle_venta;
VACUUM (ANALYZE) cliente;
VACUUM (ANALYZE) historial_puntos;
VACUUM (ANALYZE) bitacora;   -- recorre todas las particiones

-- Estadisticas de toda la base
ANALYZE;

-- Reconstruye indices inflados (usar CONCURRENTLY si la base esta en uso).
REINDEX TABLE CONCURRENTLY lote;
REINDEX TABLE CONCURRENTLY venta;
-- Reconstruir todos los indices de la base (mantenimiento completo):
-- REINDEX DATABASE CONCURRENTLY farmacia_bienestar;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 4. MONITOREO DE ESPACIO EN DISCO
-- 4.1 Tamano de la base de datos
SELECT pg_database.datname                                AS base,
       pg_size_pretty(pg_database_size(pg_database.datname)) AS tamano
  FROM pg_database
 WHERE datname = current_database();

-- 4.2 Tamano por tablespace (pg_default, ts_bitacora, ts_indices)
SELECT spcname                                AS tablespace,
       pg_size_pretty(pg_tablespace_size(spcname)) AS tamano
  FROM pg_tablespace
 ORDER BY pg_tablespace_size(spcname) DESC;

-- 4.3 Tamano por tabla: datos, indices y total
SELECT c.relname                                         AS tabla,
       pg_size_pretty(pg_table_size(c.oid))              AS datos,
       pg_size_pretty(pg_indexes_size(c.oid))            AS indices,
       pg_size_pretty(pg_total_relation_size(c.oid))     AS total
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind IN ('r', 'p')
   AND NOT c.relispartition
 ORDER BY pg_total_relation_size(c.oid) DESC;

-- 4.4 Filas muertas y ultimo vacuum/analyze 
SELECT relname                AS tabla,
       n_live_tup             AS filas_vivas,
       n_dead_tup             AS filas_muertas,
       last_autovacuum,
       last_autoanalyze
  FROM pg_stat_user_tables
 ORDER BY n_dead_tup DESC;

-- 4.5 Indices: tamano y veces que se han usado
--     (no eliminar PK ni UNIQUE; esos cumplen una restriccion)
SELECT s.relname                 AS tabla,
       s.indexrelname            AS indice,
       s.idx_scan                AS veces_usado,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS tamano
  FROM pg_stat_user_indexes s
  JOIN pg_index i ON i.indexrelid = s.indexrelid
 WHERE NOT i.indisunique
 ORDER BY s.idx_scan ASC, pg_relation_size(s.indexrelid) DESC;

-- 4.6 Confirmar que los indices estan en ts_indices y la bitacora en ts_bitacora
SELECT c.relname,
       c.relkind,
       COALESCE(t.spcname, 'pg_default') AS tablespace
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
 WHERE n.nspname = 'public'
   AND c.relkind IN ('r', 'i')
   AND (c.relname LIKE 'idx_%' OR c.relname LIKE 'bitacora%')
 ORDER BY tablespace, c.relname;