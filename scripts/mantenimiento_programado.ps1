<#
.SYNOPSIS
    Mantenimiento semanal (lo invoca el Programador de tareas).

.DESCRIPTION
    1. Ejecuta fn_mantenimiento_mensual(): crea las particiones futuras de bitacora y
       separa las que superan la retencion (definida en particionamiento.sql / mantenimiento.sql).
    2. VACUUM (ANALYZE) de toda la base.
    Deja el resultado en la carpeta de logs de los backups.
#>
[CmdletBinding()]
param(
    [string]$BaseDatos      = 'farmacia_bienestar',
    [string]$Servidor       = 'localhost',
    [int]   $Puerto         = 5432,
    [string]$Usuario        = 'postgres',
    [string]$CarpetaBackups = 'C:\Backups\farmacia_bienestar',
    [string]$PgBin          = ''
)

$ErrorActionPreference = 'Stop'
$CarpetaLogs = Join-Path $CarpetaBackups 'logs'
New-Item -ItemType Directory -Force -Path $CarpetaLogs | Out-Null
$LogFile = Join-Path $CarpetaLogs "mantenimiento_$(Get-Date -Format 'yyyy-MM').log"

function Write-Log([string]$m, [string]$n = 'INFO') {
    $l = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $n, $m
    Add-Content -Path $LogFile -Value $l -Encoding UTF8
    Write-Host $l
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
    throw 'No se encontro PostgreSQL. Indique -PgBin "C:\Program Files\PostgreSQL\16\bin"'
}

if (-not $env:PGPASSFILE) {
    foreach ($ruta in @(
            (Join-Path $PSScriptRoot 'pgpass.conf'),
            (Join-Path $env:USERPROFILE 'AppData\Roaming\postgresql\pgpass.conf'))) {
        if (Test-Path $ruta) { $env:PGPASSFILE = $ruta; break }
    }
}

function Invoke-Psql([string]$sql) {
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & $script:psql -h $Servidor -p $Puerto -U $Usuario -w -d $BaseDatos -v ON_ERROR_STOP=1 -c $sql 2>&1
        $codigo = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previo }
    $salida | ForEach-Object { Write-Log "$_" 'DEBUG' }
    if ($codigo -ne 0) { throw "psql termino con codigo $codigo" }
}

try {
    $script:psql = Join-Path (Get-PgBin) 'psql.exe'
    Write-Log "===== Inicio de mantenimiento de '$BaseDatos' ====="
    Invoke-Psql 'SELECT * FROM fn_mantenimiento_mensual();'
    Invoke-Psql 'VACUUM (ANALYZE);'
    Write-Log '===== Mantenimiento finalizado correctamente ====='
    exit 0
}
catch {
    Write-Log "FALLO EL MANTENIMIENTO: $($_.Exception.Message)" 'ERROR'
    exit 1
}
