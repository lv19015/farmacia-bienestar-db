---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Farmacia Comunitaria "Bienestar" - Verificacion de una restauracion
-- Ejecutar en la base original y en la restaurada y comparar resultados.
-- restore.ps1 lo hace automaticamente.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

-- Filas por tabla (las particiones de bitacora se suman en la tabla padre)
SELECT c.relname AS tabla,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT count(*) AS n FROM public.%I', c.relname),
                           false, true, '')))[1]::text::bigint AS filas
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind IN ('r', 'p')  -- tablas normales y particionadas
   AND NOT c.relispartition    -- excluye las particiones hijas
 ORDER BY c.relname;

-- Objetos que deben existir tras restaurar
SELECT 'triggers'   AS objeto, count(*) AS cantidad FROM pg_trigger WHERE NOT tgisinternal
UNION ALL
SELECT 'indices',   count(*) FROM pg_indexes WHERE schemaname = 'public'
UNION ALL
SELECT 'funciones', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public'
UNION ALL
SELECT 'particiones_bitacora', count(*) FROM pg_inherits WHERE inhparent = 'public.bitacora'::regclass;
