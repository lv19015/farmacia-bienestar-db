# Farmacia Comunitaria "Bienestar": Seguridad, monitoreo y alertas

## 1. Objetivo y alcance

Proteger la información de la farmacia (ventas, inventario, recetas, clientes y la bitácora de auditoría), en especial los datos de salud y personales, mediante mínimo privilegio, cifrado, una bitácora protegida y alertas automáticas. Ningún usuario de la aplicación es superusuario.

## 2. Scripts y orden de ejecución

Se ejecutan **después** de `mantenimiento.sql`: el particionamiento vuelve a crear la tabla `bitacora` y los permisos sobre ella se perderían.

| Orden | Archivo | Ubicación | Qué hace |
|---|---|---|---|
| 1 | `seguridad.sql` | `sql/` | Roles, usuarios, permisos y auditoría endurecida |
| 2 | `pruebas_seguridad.sql` | `sql/` | 31 pruebas automáticas (cada una se deshace, no cambia datos) |
| 3 | `cifrado.sql` | `sql/` | Cifra `receta.diagnostico` y `paciente.observaciones` |
| 4 | `monitoreo_alertas.sql` | `sql/` | Umbrales, tabla de alertas y `fn_verificar_alertas()` |
| 5 | `monitoreo_programado.ps1` | `scripts/` | Ejecuta las alertas cada 15 minutos y revisa accesos fallidos |

En pgAdmin se ejecuta cada archivo completo (F5). Para ver el resultado de una comprobación se selecciona esa consulta y se ejecuta sola.

## 3. Roles y permisos

Los permisos se dan a roles de grupo (sin inicio de sesión) y cada persona entra con un usuario que pertenece a uno de ellos.

| Rol | Usuario de ejemplo | Puede | No puede |
|---|---|---|---|
| `rol_admin_farmacia` | `usr_admin` | Consultar y modificar todas las tablas del negocio, incluido borrar | Tocar la bitácora, eliminar tablas, crear usuarios |
| `rol_farmaceutico` | `usr_farmaceutico1` | Registrar ventas, validar recetas, atender pacientes, ver datos clínicos | Borrar, cambiar un diagnóstico, ver compras y proveedores |
| `rol_cajero` | `usr_cajero1` | Registrar ventas y puntos; ver nombre y puntos del cliente | Ver pacientes, recetas, DUI o bitácora |
| `rol_compras` | `usr_compras1` | Gestionar proveedores, compras y recepción de lotes | Ver clientes, pacientes o ventas |
| `rol_auditor` | `usr_auditor1` | Leer el negocio y la bitácora | Modificar datos; ver DUI o datos clínicos |
| `rol_respaldo` | `usr_respaldo` | Leer las tablas para `pg_dump` | Escribir; leer las contraseñas de los usuarios |
| `rol_monitoreo` | `usr_monitor` | Ejecutar las alertas y ver estadísticas del servidor | Leer los datos del negocio |

Otras medidas:

- Permisos por columna (el cajero no ve el DUI ni el correo; el farmacéutico cambia el estado de una receta pero no su diagnóstico).
- `DELETE` solo para el administrador; nadie puede modificar ni borrar la bitácora.
- Se cierra el acceso por defecto de PUBLIC a la base, al esquema y a las funciones de mantenimiento.
- Cada usuario tiene límite de conexiones, `statement_timeout` e `idle_in_transaction_session_timeout`.
- Contraseñas guardadas con `scram-sha-256`.

> Las contraseñas de `seguridad.sql` son de **demostración** (`Cambiar_Clave_2026!`). Al desplegar se cambian con `ALTER ROLE usr_cajero1 PASSWORD '...'`.

Para comprobar: las consultas 6.1 a 6.5 de `seguridad.sql` y el resultado de `pruebas_seguridad.sql` (31 de 31 en `OK`).

## 4. Cifrado de datos sensibles

`receta.diagnostico` y `paciente.observaciones` se guardan cifradas con pgcrypto (PGP simétrico). Un trigger cifra al guardar y la aplicación no cambia.

- **La clave no está en la base:** cada sesión la entrega con `SET app.clave_cifrado = '...'`. Sin clave los datos se muestran como `[CIFRADO - sin clave]` y no se pueden guardar datos clínicos nuevos.
- **Lectura:** las vistas `v_receta_clinica` y `v_paciente_clinico` muestran el dato descifrado solo al farmacéutico y al administrador.
- **DUI:** no se cifra porque es único y se usa para buscar clientes; se protege con permisos por columna.
- **Efecto en `consultas.sql`:** dos consultas (histórico de medicamentos y pacientes crónicos) leen estas columnas; para verlas legibles se cambian por las vistas (ver sección 5 de `cifrado.sql`).
- La clave de `cifrado.sql` es de demostración. Si se pierde, los datos cifrados no se pueden recuperar; en producción se guarda en un gestor de secretos, aparte de la base y de los respaldos.

## 5. Auditoría

- `fn_auditoria_generica()` se ejecuta como su propietario (`SECURITY DEFINER`) y registra al usuario real con `session_user`. Así los usuarios no necesitan permiso sobre la bitácora y no pueden falsificarla.
- Los datos clínicos (`diagnostico`, `observaciones`, `condicion_cronica`) se registran como `[PROTEGIDO]`, para que la bitácora no sea una segunda copia de información sensible.
- Solo el auditor, el administrador y el rol de respaldo leen la bitácora.

> Este script reemplaza la versión de `fn_auditoria_generica()` de `indices_bitacora.sql`.

## 6. Monitoreo y alertas

La tabla `umbral_alerta` define 12 métricas con umbral y severidad, editables con un `UPDATE`. `fn_verificar_alertas()` las mide y registra en la tabla `alerta` las que superan su umbral.

| Grupo | Métricas |
|---|---|
| Seguridad | Superusuarios extra, contraseñas débiles (md5), cambios hechos por `postgres`, borrados en la última hora, conexiones respecto al máximo |
| Disco y mantenimiento | Tamaño de la base, tamaño de `ts_bitacora`, porcentaje de filas muertas |
| Negocio | Lotes vencidos con existencias, lotes por vencer en 60 días, productos con poco stock, facturas electrónicas pendientes o rechazadas |

`monitoreo_programado.ps1` usa `usr_monitor`, escribe en `C:\Backups\farmacia_bienestar\logs` (`monitoreo_AAAA-MM.log`) y cuenta los intentos de inicio de sesión fallidos en el log de PostgreSQL. Códigos de salida: 0 sin alertas, 1 fallo del script, 2 hay alertas ALTA, 3 solo MEDIA o BAJA.

```powershell
# Primera vez: guarda la contraseña de usr_monitor (el puerto de este equipo es 5433)
.\monitoreo_programado.ps1 -Puerto 5433 -CrearPgpass
# Ejecutar una vez
.\monitoreo_programado.ps1 -Puerto 5433
# Crear la tarea Farmacia_Monitoreo (cada 15 minutos)
.\monitoreo_programado.ps1 -Puerto 5433 -Programar
```

El espacio en disco y los índices también se revisan con las consultas 4.1 a 4.6 de `mantenimiento.sql` (ver `Mantenimiento_y_crecimiento.md`).

## 7. Seguridad de los respaldos

- `rol_respaldo` solo tiene lectura sobre las tablas de la farmacia. Un `pg_dump` con ese rol funciona, incluidas las particiones nuevas de la bitácora (`ALTER DEFAULT PRIVILEGES`).
- **Hallazgo:** con el rol predefinido `pg_read_all_data` el respaldo podía leer los hashes de contraseña (`pg_authid`). Se reemplazó por permisos tabla por tabla y una prueba automática confirma que ya no puede.
- `pg_dumpall --globals-only` con ese usuario necesita `--no-role-passwords`. El archivo `globales_*.sql` que genera `backup.ps1` con `postgres` contiene hashes de contraseña: se protege igual que el `.dump`.
- Una restauración conserva permisos, datos cifrados y conteo de filas (ver `Backup_y_restauración.md`). En un servidor nuevo se ejecuta antes `globales_*.sql` para crear los roles.
