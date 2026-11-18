# Farmacia Comunitaria "Bienestar": Backups y restauración

## 1. Objetivo y alcance

Garantizar que la información de la farmacia (ventas, inventario por lote, recetas, clientes y la bitácora de auditoría) pueda recuperarse ante borrado accidental, corrupción de datos, falla de disco o pérdida del equipo. El documento define qué se respalda, con qué frecuencia, dónde se guarda, cómo se restaura y cómo se comprueba que la restauración funciona.

## 2. Qué se respalda

| Elemento | Herramienta | Archivo generado | Por qué |
|---|---|---|---|
| Base de datos completa (tablas, datos, índices, triggers, funciones, particiones) | `pg_dump -Fc` | `farmacia_bienestar_AAAA-MM-DD_HHmmss.dump` | Backup lógico comprimido; se restaura con `pg_restore` y permite restaurar solo una tabla |
| Roles y tablespaces | `pg_dumpall --globals-only` | `globales_AAAA-MM-DD_HHmmss.sql` | `pg_dump` no incluye los `CREATE TABLESPACE` ni los roles; sin ellos el `.dump` no restaura igual en otro servidor |
| Cluster completo (opcional) | `pg_basebackup` | carpeta `fisico_AAAA-MM-DD_HHmmss` | Base para recuperación a un punto en el tiempo (PITR) |

## 3. Tipos de backup

**Lógico (`pg_dump`)**: exporta la estructura y los datos como instrucciones. Es portable entre versiones y equipos, pequeño y fácil de verificar. Es el backup principal de este proyecto. Limitación: solo recupera hasta el momento en que se hizo; lo registrado después se pierde.

**Físico (`pg_basebackup`)**: copia los archivos del cluster. Restaura más rápido en bases grandes y, combinado con el archivado de WAL (sección 8), permite volver a cualquier instante. Limitación: solo se restaura en la misma versión mayor de PostgreSQL y el mismo sistema operativo.

## 4. Frecuencia, retención y ubicación

| Parámetro | Valor | Dónde se cambia |
|---|---|---|
| Backup lógico | Diario a las 02:00 | `programar_backup.ps1 -Hora` |
| Mantenimiento (particiones, VACUUM) | Semanal, domingo 03:00 | `programar_backup.ps1` |
| Retención | 14 días (después se eliminan automáticamente) | `backup.ps1 -DiasRetencion` |
| Carpeta de backups | `C:\Backups\farmacia_bienestar` | `backup.ps1 -CarpetaBackups` |
| Logs | `C:\Backups\farmacia_bienestar\logs` | automático |
| Copia externa (recomendado) | Copiar semanalmente la carpeta a una unidad USB o a la nube (regla 3-2-1: 3 copias, 2 medios, 1 fuera del equipo) | manual |

Si el equipo está apagado a la hora programada, la tarea se ejecuta en cuanto se enciende (`StartWhenAvailable`).

## 5. RPO y RTO

- **RPO** (cuántos datos se pueden perder): con backup lógico diario, hasta 24 horas. Con PITR (sección 8), segundos o minutos.
- **RTO** (cuánto tarda en volver a operar): con el volumen actual (decenas de filas por tabla), la restauración tarda segundos; en producción real dependería del tamaño de la base y se mediría con `restore.ps1`, que reporta el tiempo.

## 6. Automatización

Orden de configuración (PowerShell como administrador, en la carpeta de los scripts):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\programar_backup.ps1 -CrearPgpass        # guarda la contraseña y crea las dos tareas
Start-ScheduledTask -TaskName Farmacia_Backup_Diario    # prueba inmediata
Get-ScheduledTaskInfo -TaskName Farmacia_Backup_Diario  # LastTaskResult = 0 significa éxito
```

- La contraseña se guarda en `%APPDATA%\postgresql\pgpass.conf` (formato `servidor:puerto:base:usuario:contraseña`) para que ningún script la lleve escrita.
- `backup.ps1` valida cada `.dump` con `pg_restore --list`, registra cada paso en el log y elimina los backups vencidos.
- Backup manual puntual: `.\backup.ps1`. Con copia física: `.\backup.ps1 -Fisico` (requiere permiso de replicación en `pg_hba.conf`).

## 7. Procedimiento de restauración

### 7.1 Restaurar en una base de prueba (verificación periódica)

```powershell
.\restore.ps1
```

El script toma el `.dump` más reciente, crea `farmacia_bienestar_restaurada`, restaura con `pg_restore` y compara el número de filas de cada tabla con la base original. Debe terminar con *"OK: todas las tablas tienen el mismo número de filas"*.

### 7.2 Recuperarse de un desastre (misma máquina o equipo nuevo)

1. Instalar PostgreSQL (misma versión mayor o superior) y registrar la contraseña.
2. Crear las carpetas de los tablespaces, **vacías**, y darle al usuario del servicio de PostgreSQL permiso de modificación sobre ellas.
3. Ejecutar en `psql` el archivo `globales_*.sql` más reciente (crea roles y tablespaces). Si las rutas del equipo nuevo son distintas, editar las rutas `LOCATION` del archivo antes de ejecutarlo.
4. Restaurar la base:
   ```powershell
   .\restore.ps1 -BaseDestino farmacia_bienestar -Reemplazar
   ```
   Si no se desea recrear los tablespaces: `.\restore.ps1 -BaseDestino farmacia_bienestar -SinTablespaces` (todo queda en `pg_default`).
5. Confirmar con la salida de verificación y con `SELECT * FROM fn_mantenimiento_mensual();`.
6. Volver a crear las tareas programadas con `programar_backup.ps1`.

### 7.3 Restaurar solo una tabla

```powershell
pg_restore -h localhost -U postgres -d farmacia_bienestar --data-only -t producto "C:\Backups\farmacia_bienestar\<archivo>.dump"
```

Útil cuando se borraron datos de una sola tabla. Conviene restaurar primero en una base de prueba y copiar las filas necesarias.

### 7.4 Consideraciones de este proyecto

- **Tablespaces**: el `.dump` indica que la bitácora va a `ts_bitacora` y los índices a `ts_indices`. Esas ubicaciones deben existir (o usar `-SinTablespaces`), de lo contrario `pg_restore` falla.
- **Extensión `pg_trgm`**: la usan los índices GIN; viene con los paquetes estándar de PostgreSQL para Windows (contrib).
- **Bitácora particionada**: `pg_restore` recrea la tabla y sus particiones. Después de restaurar en una fecha posterior, ejecutar `SELECT * FROM fn_crear_particiones_bitacora();` para tener particiones de los meses siguientes (de todos modos, la partición `DEFAULT` evita que falle cualquier inserción).
- **Rutas en Windows**: en `CREATE TABLESPACE` se usan barras normales, por ejemplo `'C:/PostgreSQL/ts/bitacora'`. Las rutas de ejemplo de `indices_bitacora.sql` (`/var/lib/postgresql/...`) son de Linux y deben ajustarse.

## 8. Recuperación a un punto en el tiempo (PITR)

Permite volver, por ejemplo, a "ayer a las 14:35, justo antes de borrar las ventas por error".

**Preparación** (`postgresql.conf`; requiere reiniciar el servicio):

```
wal_level = replica
archive_mode = on
archive_command = 'copy "%p" "C:\\pg_wal_archive\\%f"'
```

Crear antes la carpeta `C:\pg_wal_archive`. Luego tomar un backup físico base con `.\backup.ps1 -Fisico`.

**Recuperación** (resumen):

1. Detener el servicio de PostgreSQL y guardar el directorio de datos actual.
2. Restaurar el backup físico base en un directorio de datos limpio (descomprimir `base.tar.gz` y los tar de cada tablespace).
3. En `postgresql.conf` del directorio restaurado:
   ```
   restore_command = 'copy "C:\\pg_wal_archive\\%f" "%p"'
   recovery_target_time = '2026-11-16 14:35:00'
   recovery_target_action = 'promote'
   ```
4. Crear un archivo vacío llamado `recovery.signal` en el directorio de datos.
5. Iniciar el servicio: PostgreSQL reproduce el WAL hasta esa hora y queda disponible.

