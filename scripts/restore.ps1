<#
.SYNOPSIS
    Restaura un backup de farmacia_bienestar en una base nueva y verifica el resultado

.DESCRIPTION
    1. Busca el backup (.dump) mas reciente de la carpeta, o usa el indicado en -Archivo
    2. Crea la base de destino (por defecto farmacia_bienestar_restaurada) y restaura con pg_restore
    3. Ejecuta verificar_restauracion.sql en la base restaurada y, si la base original existe,
       compara el conteo de filas tabla por tabla

    NO toca la base original sino que restaura en una base de prueba
    TABLESPACES: el dump indica que bitacora y sus indices van en ts_bitacora y ts_indices.

.EXAMPLE
    .\restore.ps1
.EXAMPLE
    .\restore.ps1 -Archivo "C:\Backups\farmacia_bienestar\farmacia_bienestar_2026-11-16_020000.dump"
.EXAMPLE
    .\restore.ps1 -SinTablespaces -Reemplazar
#>
[CmdletBinding()]
param(
    [string]$Archivo         = '',      # .dump a restaurar; si se omite, el mas reciente
    [string]$BaseOriginal    = 'farmacia_bienestar',
    [string]$BaseDestino     = 'farmacia_bienestar_restaurada',
    [string]$Servidor        = 'localhost',
    [int]   $Puerto          = 5432,
    [string]$Usuario         = 'postgres',
    [string]$CarpetaBackups  = 'C:\Backups\farmacia_bienestar',
    [string]$PgBin           = '',
    [switch]$SinTablespaces,            # ignora TABLESPACE del dump (util en otro servidor)
    [switch]$Reemplazar                 # elimina la base de destino si ya existe
)

$ErrorActionPreference = 'Stop'

function Get-PgBin {
    if ($PgBin -and (Test-Path (Join-Path $PgBin 'pg_restore.exe'))) { return $PgBin }
    $base = Join-Path $env:ProgramFiles 'PostgreSQL'
    if (Test-Path $base) {
        $c = Get-ChildItem $base -Directory |
             Sort-Object { [int]($_.Name -replace '\D', '0') } -Descending |
             ForEach-Object { Join-Path $_.FullName 'bin' } |
             Where-Object { Test-Path (Join-Path $_ 'pg_restore.exe') } |
             Select-Object -First 1
        if ($c) { return $c }
    }
    $cmd = Get-Command pg_restore.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    throw 'No se encontro PostgreSQL. Indique la carpeta bin con -PgBin "C:\Program Files\PostgreSQL\16\bin"'
}

if (-not $env:PGPASSFILE) {
    foreach ($ruta in @(
            (Join-Path $PSScriptRoot 'pgpass.conf'),
            (Join-Path $env:USERPROFILE 'AppData\Roaming\postgresql\pgpass.conf'))) {
        if (Test-Path $ruta) { $env:PGPASSFILE = $ruta; break }
    }
}

# Ejecuta un programa de PostgreSQL; devuelve la salida y falla si el codigo de salida != 0
function Invoke-Pg {
    param([string]$Exe, [string[]]$Argumentos, [switch]$PermitirAdvertencias)
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'      # PS 5.1: stderr no debe convertirse en excepcion
    try {
        $salida = & $Exe @Argumentos 2>&1
        $codigo = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previo }
    if ($codigo -ne 0 -and -not $PermitirAdvertencias) {
        throw "$(Split-Path $Exe -Leaf) termino con codigo ${codigo}: $($salida -join ' ')"
    }
    return $salida
}

function Test-BaseExiste([string]$nombre) {
    $r = Invoke-Pg $psql ($conexion + @('-d', 'postgres', '-t', '-A', '-c',
          "SELECT 1 FROM pg_database WHERE datname = '$nombre'"))
    return (($r | Out-String).Trim() -eq '1')
}

# Devuelve el conteo de filas por tabla de una base: hashtable tabla -> filas
function Get-Conteo([string]$base) {
    $sql = Join-Path $PSScriptRoot 'verificar_restauracion.sql'
    $filas = Invoke-Pg $psql ($conexion + @('-d', $base, '-t', '-A', '-F', '|', '-f', $sql))
    $h = [ordered]@{}
    foreach ($l in $filas) {
        $t = "$l".Split('|')
        if ($t.Count -eq 2 -and $t[1] -match '^\d+$') { $h[$t[0]] = [int64]$t[1] }
    }
    return $h
}

# *-*-* EJECUCIÓN *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
$bin      = Get-PgBin
$psql     = Join-Path $bin 'psql.exe'
$restore  = Join-Path $bin 'pg_restore.exe'
$conexion = @('-h', $Servidor, '-p', $Puerto, '-U', $Usuario, '-w')

# 1. Elegir el backup
if (-not $Archivo) {
    $ultimo = Get-ChildItem $CarpetaBackups -Filter "${BaseOriginal}_*.dump" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $ultimo) { throw "No hay archivos .dump en $CarpetaBackups. Ejecute backup.ps1 primero." }
    $Archivo = $ultimo.FullName
}
if (-not (Test-Path $Archivo)) { throw "No existe el archivo: $Archivo" }
Write-Host "Backup a restaurar : $Archivo"
Write-Host "Base de destino    : $BaseDestino"

if ($BaseDestino -eq $BaseOriginal -and -not $Reemplazar) {
    throw 'El destino es la base original. Use otro nombre en -BaseDestino o agregue -Reemplazar si realmente desea sobrescribirla.'
}

# 2. Preparar la base de destino
if (Test-BaseExiste $BaseDestino) {
    if (-not $Reemplazar) { throw "La base '$BaseDestino' ya existe. Use -Reemplazar para eliminarla y volver a crearla." }
    Write-Host "Eliminando base existente '$BaseDestino'..."
    # Cierra conexiones abiertas y elimina
    Invoke-Pg $psql ($conexion + @('-d', 'postgres', '-c',
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$BaseDestino' AND pid <> pg_backend_pid()")) | Out-Null
    Invoke-Pg $psql ($conexion + @('-d', 'postgres', '-c', "DROP DATABASE `"$BaseDestino`"")) | Out-Null
}
Write-Host 'Creando base de destino...'
Invoke-Pg $psql ($conexion + @('-d', 'postgres', '-c', "CREATE DATABASE `"$BaseDestino`"")) | Out-Null

# 3. Restaurar
$argsRestore = $conexion + @('-d', $BaseDestino, '--no-owner', '--exit-on-error')
if ($SinTablespaces) { $argsRestore += '--no-tablespaces' }
$argsRestore += $Archivo
Write-Host 'Restaurando con pg_restore (puede tardar)...'
$inicio = Get-Date
Invoke-Pg $restore $argsRestore | Out-Null
Write-Host ("Restauracion terminada en {0:N1} s" -f ((Get-Date) - $inicio).TotalSeconds) -ForegroundColor Green

# 4. Verificacion
Write-Host "`n--- Verificacion: filas por tabla ---"
$rest = Get-Conteo $BaseDestino
$rest.GetEnumerator() | ForEach-Object { '{0,-20} {1,8}' -f $_.Key, $_.Value } | Write-Host

if (($BaseOriginal -ne $BaseDestino) -and (Test-BaseExiste $BaseOriginal)) {
    Write-Host "`n--- Comparacion con la base original '$BaseOriginal' ---"
    $orig = Get-Conteo $BaseOriginal
    $difs = @()
    foreach ($t in $orig.Keys) {
        if (-not $rest.Contains($t) -or $rest[$t] -ne $orig[$t]) {
            $difs += ('{0}: original={1}, restaurada={2}' -f $t, $orig[$t], $(if ($rest.Contains($t)) { $rest[$t] } else { 'NO EXISTE' }))
        }
    }
    if ($difs.Count -eq 0) {
        Write-Host 'OK: todas las tablas tienen el mismo numero de filas.' -ForegroundColor Green
    } else {
        Write-Host 'Diferencias encontradas (normal si hubo cambios despues del backup):' -ForegroundColor Yellow
        $difs | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    }
} else {
    Write-Host "`n(La base original no existe o es el mismo destino: no se compara.)"
}
