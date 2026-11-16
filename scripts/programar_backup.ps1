<#
.SYNOPSIS
    Programa el backup diario y el mantenimiento semanal en el Programador de tareas de Windows.

.DESCRIPTION
    Crea dos tareas:
      - "Farmacia_Backup_Diario"        -> ejecuta backup.ps1 todos los dias a la hora indicada.
      - "Farmacia_Mantenimiento_Semanal" -> ejecuta mantenimiento_programado.ps1 los domingos.
    Ambas usan -StartWhenAvailabl
    -CrearPgpass guarda la contrasena de PostgreSQL en %APPDATA%\postgresql\pgpass.conf
    para que los scripts no la pidan ni la lleven escrita.
    Ejecutar PowerShell COMO ADMINISTRADOR

.EXAMPLE
    .\programar_backup.ps1 -CrearPgpass    # primera vez: guarda contrasena y programa
.EXAMPLE
    .\programar_backup.ps1 -Hora 23:30
.EXAMPLE
    .\programar_backup.ps1 -Quitar     # elimina las tareas
.EXAMPLE
    Start-ScheduledTask -TaskName Farmacia_Backup_Diario   # ejecutar una vez para probar
#>
[CmdletBinding()]
param(
    [string]$Hora      = '02:00',     # hora del backup diario (HH:mm)
    [string]$Servidor  = 'localhost',
    [int]   $Puerto    = 5432,
    [string]$Usuario   = 'postgres',
    [string]$BaseDatos = 'farmacia_bienestar',
    [switch]$CrearPgpass,
    [switch]$Quitar
)

$ErrorActionPreference = 'Stop'
$tareaBackup = 'Farmacia_Backup_Diario'
$tareaMant   = 'Farmacia_Mantenimiento_Semanal'

if ($Quitar) {
    foreach ($t in @($tareaBackup, $tareaMant)) {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $t -Confirm:$false
            Write-Host "Tarea eliminada: $t"
        }
    }
    return
}

# *-*-* Contrasena (pgpass.conf) *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
if ($CrearPgpass) {
    $carpeta = Join-Path $env:APPDATA 'postgresql'
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
    $segura = Read-Host "Contrasena del usuario '$Usuario' de PostgreSQL" -AsSecureString
    $plana  = [System.Net.NetworkCredential]::new('', $segura).Password
    # Formato: servidor:puerto:base:usuario:contrasena  (* = cualquier base)
    $linea  = "${Servidor}:${Puerto}:*:${Usuario}:${plana}"
    # PostgreSQL en Windows espera el archivo sin BOM
    [System.IO.File]::WriteAllText((Join-Path $carpeta 'pgpass.conf'), $linea + "`n",
                                   (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Contrasena guardada en $carpeta\pgpass.conf" -ForegroundColor Green
}

# *-*-* Tareas programadas *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
$scriptBackup = Join-Path $PSScriptRoot 'backup.ps1'
$scriptMant   = Join-Path $PSScriptRoot 'mantenimiento_programado.ps1'
foreach ($s in @($scriptBackup, $scriptMant)) {
    if (-not (Test-Path $s)) { throw "No se encuentra $s. Deje todos los scripts en la misma carpeta." }
}

$ps = (Get-Command powershell.exe).Source
$comun = "-NoProfile -ExecutionPolicy Bypass -File"
$param = "-Servidor $Servidor -Puerto $Puerto -Usuario $Usuario -BaseDatos $BaseDatos"

$ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
              -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
              -LogonType Interactive -RunLevel Limited

# Backup diario
$accion  = New-ScheduledTaskAction -Execute $ps -Argument "$comun `"$scriptBackup`" $param"
$trigger = New-ScheduledTaskTrigger -Daily -At $Hora
Register-ScheduledTask -TaskName $tareaBackup -Action $accion -Trigger $trigger `
    -Settings $ajustes -Principal $principal -Force `
    -Description 'Backup diario de farmacia_bienestar (pg_dump + globales)' | Out-Null
Write-Host "Tarea creada: $tareaBackup (todos los dias a las $Hora)" -ForegroundColor Green

# Mantenimiento semanal (domingo 03:00)
$accion2  = New-ScheduledTaskAction -Execute $ps -Argument "$comun `"$scriptMant`" $param"
$trigger2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00'
Register-ScheduledTask -TaskName $tareaMant -Action $accion2 -Trigger $trigger2 `
    -Settings $ajustes -Principal $principal -Force `
    -Description 'Particiones de bitacora, VACUUM y ANALYZE de farmacia_bienestar' | Out-Null
Write-Host "Tarea creada: $tareaMant (domingos a las 03:00)" -ForegroundColor Green

Write-Host "`nProbar ahora:  Start-ScheduledTask -TaskName $tareaBackup"
Write-Host "Ver resultado: Get-ScheduledTaskInfo -TaskName $tareaBackup"
