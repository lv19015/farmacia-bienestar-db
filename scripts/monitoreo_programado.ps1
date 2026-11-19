<#
.SYNOPSIS
    Monitoreo y alertas de farmacia_bienestar (lo invoca el Programador de tareas).

.DESCRIPTION
    1. Ejecuta fn_verificar_alertas() con el usuario de monitoreo (usr_monitor) y
       escribe en el log cada metrica que supera su umbral (ver monitoreo_alertas.sql).
    2. Revisa el log de PostgreSQL buscando intentos de inicio de sesion fallidos
       en los ultimos minutos y alerta si superan el limite.
    Deja el resultado en la carpeta de logs de los backups (monitoreo_AAAA-MM.log).

    Codigos de salida (se ven como "Resultado de la ultima ejecucion" en el
    Programador de tareas):
        0 = sin alertas      1 = fallo del script
        2 = hay alertas de severidad ALTA      3 = solo alertas MEDIA o BAJA

    La contrasena NO va en el script: se toma de pgpass.conf (igual que backup.ps1).
    -CrearPgpass agrega la linea del usuario de monitoreo sin borrar las demas.
    -Programar crea la tarea "Farmacia_Monitoreo" que se repite cada 15 minutos.
    Ejecutar PowerShell COMO ADMINISTRADOR para -Programar.

.EXAMPLE
    .\monitoreo_programado.ps1 -CrearPgpass     # primera vez: guarda la contrasena de usr_monitor
.EXAMPLE
    .\monitoreo_programado.ps1                  # ejecutar una vez a mano
.EXAMPLE
    .\monitoreo_programado.ps1 -Programar       # revisar cada 15 minutos
.EXAMPLE
    .\monitoreo_programado.ps1 -Quitar          # elimina la tarea
#>
[CmdletBinding()]
param(
    [string]$BaseDatos       = 'farmacia_bienestar',
    [string]$Servidor        = 'localhost',
    [int]   $Puerto          = 5432,
    [string]$Usuario         = 'usr_monitor',
    [string]$CarpetaBackups  = 'C:\Backups\farmacia_bienestar',   # aqui se guardan los logs
    [string]$CarpetaLogPg    = '',      # carpeta log de PostgreSQL; si se omite, se detecta sola
    [int]   $MaxFallosLogin  = 5,       # alerta si hay este numero de fallos o mas...
    [int]   $VentanaMinutos  = 60,      # ...dentro de esta ventana de tiempo
    [int]   $CadaMinutos     = 15,      # frecuencia de la tarea programada
    [string]$PgBin           = '',
    [switch]$CrearPgpass,
    [switch]$Programar,
    [switch]$Quitar
)

$ErrorActionPreference = 'Stop'
$nombreTarea = 'Farmacia_Monitoreo'

# *-*-* TAREA PROGRAMADA Y CONTRASENA *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
if ($Quitar) {
    if (Get-ScheduledTask -TaskName $nombreTarea -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $nombreTarea -Confirm:$false
        Write-Host "Tarea eliminada: $nombreTarea"
    }
    return
}

if ($CrearPgpass) {
    $carpeta = Join-Path $env:APPDATA 'postgresql'
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
    $archivo = Join-Path $carpeta 'pgpass.conf'
    $segura  = Read-Host "Contrasena del usuario '$Usuario' de PostgreSQL" -AsSecureString
    $plana   = [System.Net.NetworkCredential]::new('', $segura).Password
    $linea   = "${Servidor}:${Puerto}:*:${Usuario}:${plana}"
    # Conserva las lineas de otros usuarios (por ejemplo postgres) y reemplaza solo la de este
    $otras = @()
    if (Test-Path $archivo) {
        $otras = @(Get-Content $archivo | Where-Object { $_ -and $_ -notlike "${Servidor}:${Puerto}:*:${Usuario}:*" })
    }
    $contenido = (($otras + $linea) -join "`n") + "`n"
    [System.IO.File]::WriteAllText($archivo, $contenido, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Contrasena de '$Usuario' guardada en $archivo" -ForegroundColor Green
}

if ($Programar) {
    $ps     = (Get-Command powershell.exe).Source
    $script = $PSCommandPath
    $arg    = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Servidor $Servidor -Puerto $Puerto -Usuario $Usuario -BaseDatos $BaseDatos -CarpetaBackups `"$CarpetaBackups`""
    $accion  = New-ScheduledTaskAction -Execute $ps -Argument $arg
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                  -RepetitionInterval (New-TimeSpan -Minutes $CadaMinutos) `
                  -RepetitionDuration (New-TimeSpan -Days 3650)
    $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                  -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                  -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $nombreTarea -Action $accion -Trigger $trigger `
        -Settings $ajustes -Principal $principal -Force `
        -Description 'Alertas de seguridad, disco y negocio de farmacia_bienestar' | Out-Null
    Write-Host "Tarea creada: $nombreTarea (cada $CadaMinutos minutos)" -ForegroundColor Green
    Write-Host "Probar ahora:  Start-ScheduledTask -TaskName $nombreTarea"
    Write-Host "Ver resultado: Get-ScheduledTaskInfo -TaskName $nombreTarea"
    return
}

if ($CrearPgpass) { return }

# *-*-* PREPARACION *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
$CarpetaLogs = Join-Path $CarpetaBackups 'logs'
New-Item -ItemType Directory -Force -Path $CarpetaLogs | Out-Null
$LogFile = Join-Path $CarpetaLogs "monitoreo_$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Mensaje, [string]$Nivel = 'INFO')
    $linea = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje
    Add-Content -Path $LogFile -Value $linea -Encoding UTF8
    switch ($Nivel) {
        'ERROR' { Write-Host $linea -ForegroundColor Red }
        'WARN'  { Write-Host $linea -ForegroundColor Yellow }
        default { Write-Host $linea }
    }
}

function Get-PgBin {
    if ($PgBin -and (Test-Path (Join-Path $PgBin 'psql.exe'))) { return $PgBin }
    $base = Join-Path $env:ProgramFiles 'PostgreSQL'
    if (Test-Path $base) {
        $c = Get-ChildItem $base -Directory |
             Sort-Object { [int]($_.Name -replace '\D', '0') } -Descending |
             ForEach-Object { Join-Path $_.FullName 'bin' } |
             Where-Object { Test-Path (Join-Path $_ 'psql.exe') } |
             Select-Object -First 1
        if ($c) { return $c }
    }
    $cmd = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    throw 'No se encontro PostgreSQL. Indique la carpeta bin con -PgBin "C:\Program Files\PostgreSQL\18\bin"'
}

# Ubica la carpeta de logs del servidor (C:\Program Files\PostgreSQL\<version>\data\log)
function Get-CarpetaLogPg {
    if ($CarpetaLogPg -and (Test-Path $CarpetaLogPg)) { return $CarpetaLogPg }
    $base = Join-Path $env:ProgramFiles 'PostgreSQL'
    if (Test-Path $base) {
        $c = Get-ChildItem $base -Directory |
             Sort-Object { [int]($_.Name -replace '\D', '0') } -Descending |
             ForEach-Object { Join-Path $_.FullName 'data\log' } |
             Where-Object { Test-Path $_ } |
             Select-Object -First 1
        if ($c) { return $c }
    }
    return $null
}

if (-not $env:PGPASSFILE) {
    foreach ($ruta in @(
            (Join-Path $PSScriptRoot 'pgpass.conf'),
            (Join-Path $env:USERPROFILE 'AppData\Roaming\postgresql\pgpass.conf'))) {
        if (Test-Path $ruta) { $env:PGPASSFILE = $ruta; break }
    }
}

# *-*-* EJECUCION *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
$hayAlta  = $false
$hayOtras = $false
Write-Log "===== Inicio de monitoreo de '$BaseDatos' (usuario $Usuario) ====="

try {
    $psql = Join-Path (Get-PgBin) 'psql.exe'

    # 1. Alertas de la base de datos
    $sql = 'SELECT severidad_alerta, metrica_alerta, valor_actual, umbral_definido, detalle_alerta FROM fn_verificar_alertas()'
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & $psql -h $Servidor -p $Puerto -U $Usuario -w -d $BaseDatos -X -v ON_ERROR_STOP=1 -t -A -F '|' -c $sql 2>&1
        $codigo = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previo }
    if ($codigo -ne 0) { throw "psql termino con codigo ${codigo}: $($salida -join ' ')" }

    $total = 0
    foreach ($fila in $salida) {
        $t = "$fila".Split('|')
        if ($t.Count -lt 5) { continue }
        $total++
        $msg = '{0}: valor {1} supera el umbral {2}. {3}' -f $t[1], $t[2], $t[3], $t[4]
        if ($t[0] -eq 'ALTA') { $hayAlta = $true;  Write-Log "ALERTA ALTA - $msg" 'ERROR' }
        else                  { $hayOtras = $true; Write-Log "ALERTA $($t[0]) - $msg" 'WARN' }
    }
    if ($total -eq 0) { Write-Log 'Metricas de la base de datos dentro de los umbrales' }

    # 2. Intentos de inicio de sesion fallidos (se buscan en el log de PostgreSQL)
    $carpetaPg = Get-CarpetaLogPg
    if (-not $carpetaPg) {
        Write-Log 'No se encontro la carpeta de logs de PostgreSQL; indique -CarpetaLogPg' 'WARN'
    } else {
        $logPg = Get-ChildItem $carpetaPg -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($logPg) {
            $desde  = (Get-Date).AddMinutes(-$VentanaMinutos)
            $patron = 'FATAL:.*(authentication failed|autentificaci.n .*fall|autenticaci.n .*fall)'
            $fallos = @()
            foreach ($l in (Get-Content $logPg.FullName -Tail 20000 -ErrorAction SilentlyContinue)) {
                if ($l -notmatch $patron) { continue }
                $momento = [datetime]::MinValue
                if ($l.Length -ge 19 -and [datetime]::TryParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None, [ref]$momento)) {
                    if ($momento -ge $desde) { $fallos += $l }
                }
            }
            if ($fallos.Count -ge $MaxFallosLogin) {
                $hayAlta = $true
                Write-Log ("ALERTA ALTA - {0} intentos de acceso fallidos en los ultimos {1} min (limite {2}). Revise {3}" -f `
                           $fallos.Count, $VentanaMinutos, $MaxFallosLogin, $logPg.FullName) 'ERROR'
            } else {
                Write-Log ("Intentos de acceso fallidos en {0} min: {1} (limite {2})" -f $VentanaMinutos, $fallos.Count, $MaxFallosLogin)
            }
        }
    }

    Write-Log '===== Monitoreo finalizado ====='
    if ($hayAlta)  { exit 2 }
    if ($hayOtras) { exit 3 }
    exit 0
}
catch {
    Write-Log "FALLO EL MONITOREO: $($_.Exception.Message)" 'ERROR'
    exit 1
}
