# Farmacia Comunitaria "Bienestar" - Base de datos PostgreSQL

Proyecto final de **Administración de Bases de Datos**
Universidad de El Salvador - Facultad Multidisciplinaria de Occidente
Ingeniería en Desarrollo de Software / Educación en Línea - Ciclo II 2026

**Grupo:** G05 - Escenario 1: Farmacia Comunitaria "Bienestar"

## Integrantes

| Carnet  | Integrante                              |
|---------|-----------------------------------------|
| AB25013 | Catherine Andrea Argumedo Barahona      |
| HJ23002 | Paola Sugey Hércules Jirón              |
| LV19015 | Brenda Ivania Laínez Vides              |
| CC24073 | Christian Alejandro Contreras Chiquillo |

## Descripción

Diseño e implementación de la base de datos de una farmacia comunitaria, que
cubre:

- Productos, lotes y control de caducidad
- Proveedores y compras
- Ventas y reporte mensual de ventas
- Recetas médicas y seguimiento de pacientes (incluye pacientes crónicos)
- Programa de fidelización con puntos
- Promociones y descuentos
- Estructura para facturación electrónica (DTE)


## Pasos del proyecto
 
1. **Análisis de requerimientos y diseño del modelo ER**
2. **Implementación de la base de datos en PostgreSQL**: tablas, relaciones y restricciones.
3. **Auditoría e índices**: bitácora automática, tablespaces e índices.
4. **Datos de prueba**: al menos 10 registros por tabla.
5. **Optimización de consultas**: pruebas con `EXPLAIN ANALYZE` antes y después de los índices.
6. **Espacio en disco y mantenibilidad**: particionamiento, respaldos automáticos y restauración.
7. **Seguridad**: roles y permisos, encriptación, monitoreo y alertas.
8. **Informe final y presentación**.

## Mantenimiento y respaldos
 
El paso 6 **(Espacio en disco y mantenibilidad)** se resuelve con scripts de SQL y de PowerShell y cada script se ejecuta en el siguiente orden:
 
### Scripts SQL
 
| Script | Función |
|---|---|
| `particionamiento.sql` | Convierte `bitacora` en una tabla particionada por mes (en `ts_bitacora`), con partición `DEFAULT` y funciones para crear particiones futuras y archivar las que superan 12 meses |
| `mantenimiento.sql` | Ajusta autovacuum en las tablas con más movimiento, incluye `VACUUM`/`REINDEX` y consultas de monitoreo del espacio (por tabla, tablespace e índice) |
| `verificar_restauracion.sql` | Conteo de filas por tabla para comparar la base original con la restaurada |
 
### Scripts PowerShell
 
| Script | Función |
|---|---|
| `backup.ps1` | Backup lógico con `pg_dump -Fc`, respaldo de roles y tablespaces (`pg_dumpall --globals-only`), validación del archivo, rotación a 14 días y log. La opción `-Fisico` agrega un backup físico con `pg_basebackup` |
| `restore.ps1` | Restaura el último backup en una base de prueba y compara las filas con la original; `-SinTablespaces` permite restaurar en otro equipo |
| `programar_backup.ps1` | Crea en el Programador de tareas de Windows el backup diario (02:00) y el mantenimiento semanal; `-CrearPgpass` guarda la contraseña para que los scripts no la pidan |
| `mantenimiento_programado.ps1` | Tarea semanal: crea y archiva particiones de la bitácora y ejecuta `VACUUM (ANALYZE)` |


### Cómo ejecutar
 
Antes de ejecutar, las rutas de `CREATE TABLESPACE` en `indices_bitacora.sql` deben ser
rutas de Windows con barras normales (por ejemplo `'C:/PostgreSQL/ts/bitacora'`), con las carpetas
creadas y vacías.
 
```powershell
# PowerShell como administrador, en la carpeta de los scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
 
.\programar_backup.ps1 -CrearPgpass                    # contraseña + tareas programadas
Start-ScheduledTask -TaskName Farmacia_Backup_Diario   # prueba inmediata
.\restore.ps1                                          # restauración de prueba y verificación
```
 
