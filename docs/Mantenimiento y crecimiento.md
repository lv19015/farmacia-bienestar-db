# Farmacia Comunitaria "Bienestar": Gestión del crecimiento y mantenimiento

## 1. Qué tablas crecen y a qué ritmo

| Tabla | Tipo de crecimiento | Riesgo si no se gestiona | Tratamiento |
|---|---|---|---|
| `bitacora` | Solo agrega; una fila por cada INSERT/UPDATE/DELETE en `venta`, `lote`, `compra`, `producto`, `paciente` y `receta`, con JSONB antes/después | Es la tabla que más crece; consultas y backups cada vez más lentos | Partición mensual, retención de 12 meses, tablespace propio |
| `venta` y `detalle_venta` | Crecen con cada venta; `venta` se consulta por `fecha_hora` | Reportes mensuales lentos | Índice por fecha, autovacuum ajustado; no se particiona (la PK tendría que incluir la fecha y rompe las FK de `detalle_venta`, `venta_promocion` y `factura_dte`) |
| `lote` | Una fila por lote recibido; `stock_actual` se actualiza en cada venta | Filas muertas (bloat) por los UPDATE frecuentes | Autovacuum agresivo (5 %), `REINDEX` periódico |
| `historial_puntos` | Una fila por movimiento de puntos | Crecimiento sostenido | Autovacuum ajustado; candidata a particionar por `fecha_movimiento` si supera el millón de filas (no tiene llaves foráneas entrantes) |
| `factura_dte` | Una por venta, con `json_dte` (JSONB) que es la columna más pesada | Tamaño por fila alto | Monitoreo de tamaño; TOAST comprime el JSONB automáticamente |
| Catálogos (`producto`, `proveedor`, `cliente`, `promocion`) | Crecimiento lento | Bajo | Solo mantenimiento general |


## 2. Estrategias de control del crecimiento

1. **Particionamiento de `bitacora`** (`particionamiento.sql`): una partición por mes en `ts_bitacora`. Las consultas con filtro de fecha solo leen la partición necesaria, y el archivado se hace con `DETACH` en lugar de `DELETE` masivos.
2. **Separación física con tablespaces**: bitácora en `ts_bitacora` e índices en `ts_indices`, de modo que cada uno puede crecer o moverse a otro disco sin tocar los datos.
3. **Retención y archivado**: las particiones de bitácora con más de 12 meses se separan (`fn_archivar_particiones_bitacora`), quedan como tablas `arch_bitacora_AAAA_MM`, se exportan con `pg_dump` y después se eliminan.
4. **Índices con criterio**: B-tree en llaves foráneas y fechas, hash para igualdad exacta, trigramas solo en `producto.nombre` y `cliente.nombre`. Cada índice extra cuesta espacio y ralentiza las escrituras, por lo que se revisa trimestralmente cuáles no se usan.
5. **Autovacuum por tabla** (`mantenimiento.sql`): umbrales del 5 % en `lote`, `venta` y `detalle_venta`, y 10 % en `cliente` e `historial_puntos`.
6. **Restricciones de dominio** (`CHECK`, tipos acotados): evitan datos basura que ocupan espacio sin valor.

## 3. Procesos de mantenimiento

| Frecuencia | Proceso | Cómo se ejecuta | Qué logra |
|---|---|---|---|
| Diario (02:00) | Backup lógico + globales, validación y rotación a 14 días | Tarea `Farmacia_Backup_Diario` → `backup.ps1` | Recuperación ante pérdida de datos |
| Semanal (domingo 03:00) | `fn_mantenimiento_mensual()` y `VACUUM (ANALYZE)` | Tarea `Farmacia_Mantenimiento_Semanal` → `mantenimiento_programado.ps1` | Crea particiones de los próximos 3 meses, archiva las vencidas y actualiza estadísticas |
| Mensual | Revisión de tamaños y de índices sin uso | Consultas 4.1 a 4.6 de `mantenimiento.sql` | Detectar crecimiento anómalo y decidir ajustes |
| Mensual | Restauración de prueba | `.\restore.ps1` | Confirmar que el último backup realmente restaura |
| Trimestral | `REINDEX TABLE CONCURRENTLY` en `lote` y `venta` | `mantenimiento.sql`, sección 3 | Recuperar el espacio de índices inflados |
| Anual | Exportar y eliminar particiones `arch_bitacora_*`; revisar retención y capacidad de disco | `pg_dump -t arch_bitacora_AAAA_MM -Fc` y luego `DROP TABLE` | Liberar disco conservando el histórico fuera de línea |

Todos los resultados quedan en `C:\Backups\farmacia_bienestar\logs` (`backup_AAAA-MM.log` y `mantenimiento_AAAA-MM.log`).

