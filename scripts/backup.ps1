<#
.SYNOPSIS
    Backup de la base de datos farmacia_bienestar (PostgreSQL en Windows).

.DESCRIPTION
    Genera, con la fecha en el nombre:
      1. Backup logico de la base -> farmacia_bienestar_AAAA-MM-DD_HHmmss.dump
      2. Objetos globales: roles y definicion de tablespaces -> globales_AAAA-MM-DD_HHmmss.sql
      3. (Opcional, -Fisico) Backup fisico del cluster completo con pg_basebackup
    Luego valida que el .dump se pueda leer, borra los backups mas viejos que -DiasRetencion y deja un log de la ejecucion.

    La contraseña NO va en el script sino que se toma del archivo pgpass.conf

.EXAMPLE
    .\backup.ps1
.EXAMPLE
    .\backup.ps1 -CarpetaBackups "D:\Respaldos" -DiasRetencion 30
.EXAMPLE
    .\backup.ps1 -Fisico
#>
[CmdletBinding()]
param(
    [string]$BaseDatos       = 'farmacia_bienestar',
    [string]$Servidor        = 'localhost',
    [int]   $Puerto          = 5432,
    [string]$Usuario         = 'postgres',
    [string]$CarpetaBackups  = 'C:\Backups\farmacia_bienestar',
    [int]   $DiasRetencion   = 14,
    [string]$PgBin           = '',      # carpeta bin de PostgreSQL; si se omite, se detecta sola
    [switch]$Fisico                     # ademas, backup fisico con pg_basebackup
)

$ErrorActionPreference = 'Stop'

# *-*-* PREPARACIÓN *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
New-Item -ItemType Directory -Force -Path $CarpetaBackups | Out-Null
$CarpetaLogs = Join-Path $CarpetaBackups 'logs'
New-Item -ItemType Directory -Force -Path $CarpetaLogs | Out-Null

$marca   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$LogFile = Join-Path $CarpetaLogs "backup_$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Mensaje, [string]$Nivel = 'INFO')
    $linea = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje
    Add-Content -Path $LogFile -Value $linea -Encoding UTF8
    if ($Nivel -eq 'ERROR') { Write-Host $linea -ForegroundColor Red } else { Write-Host $linea }
}

# Ubica la carpeta bin de PostgreSQL (la version mas reciente instalada)
function Get-PgBin {
    if ($PgBin -and (Test-Path (Join-Path $PgBin 'pg_dump.exe'))) { return $PgBin }
    $base = Join-Path $env:ProgramFiles 'PostgreSQL'
    if (Test-Path $base) {
        $c = Get-ChildItem $base -Directory |
             Sort-Object { [int]($_.Name -replace '\D', '0') } -Descending |
             ForEach-Object { Join-Path $_.FullName 'bin' } |
             Where-Object { Test-Path (Join-Path $_ 'pg_dump.exe') } |
             Select-Object -First 1
        if ($c) { return $c }
    }
    $cmd = Get-Command pg_dump.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    throw 'No se encontro PostgreSQL. Indique la carpeta bin con -PgBin "C:\Program Files\PostgreSQL\16\bin"'
}

# Ubica el archivo de contrasenas para que funcione tambien desde el Programador de tareas
if (-not $env:PGPASSFILE) {
    foreach ($ruta in @(
            (Join-Path $PSScriptRoot 'pgpass.conf'),
            (Join-Path $env:USERPROFILE 'AppData\Roaming\postgresql\pgpass.conf'))) {
        if (Test-Path $ruta) { $env:PGPASSFILE = $ruta; break }
    }
}

# Ejecuta un programa de PostgreSQL y falla si devuelve error
function Invoke-Pg {
    param([string]$Exe, [string[]]$Argumentos)
    # En Windows PowerShell 5.1, con 'Stop' cualquier texto por stderr (p. ej. el progreso de
    # pg_basebackup) se vuelve error; se baja a 'Continue' y se valida el codigo de salida.
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Argumentos 2>&1 | ForEach-Object { Write-Log "$_" 'DEBUG' }
        $codigo = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previo }
    if ($codigo -ne 0) { throw "$(Split-Path $Exe -Leaf) termino con codigo $codigo" }
}


# *-*-* EJECUCIÓN *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*
$inicio = Get-Date
$dumpValido = $false
Write-Log "===== Inicio de backup de '$BaseDatos' en ${Servidor}:$Puerto ====="

try {
    $bin = Get-PgBin
    Write-Log "PostgreSQL bin: $bin"
    $conexion = @('-h', $Servidor, '-p', $Puerto, '-U', $Usuario, '-w')   # -w: nunca pedir contrasena

    # 1. Backup logico de la base (formato custom: comprimido y restaurable con pg_restore)
    $dump = Join-Path $CarpetaBackups "${BaseDatos}_$marca.dump"
    Invoke-Pg (Join-Path $bin 'pg_dump.exe') ($conexion + @('-Fc', '-Z', '6', '-f', $dump, $BaseDatos))
    $mb = [math]::Round((Get-Item $dump).Length / 1MB, 2)
    Write-Log "Backup logico creado: $dump ($mb MB)"

    # Validacion: pg_restore debe poder leer el indice del archivo
    & (Join-Path $bin 'pg_restore.exe') --list $dump *> $null
    if ($LASTEXITCODE -ne 0) { throw "El archivo $dump no paso la validacion de pg_restore --list" }
    Write-Log 'Validacion del .dump correcta (pg_restore --list)'
    $dumpValido = $true

    # 2. Objetos globales: roles y CREATE TABLESPACE (pg_dump no los incluye)
    $globales = Join-Path $CarpetaBackups "globales_$marca.sql"
    Invoke-Pg (Join-Path $bin 'pg_dumpall.exe') ($conexion + @('--globals-only', '-f', $globales))
    Write-Log "Globales (roles y tablespaces) creados: $globales"

    # 3. Backup fisico opcional (base para recuperacion PITR)
    if ($Fisico) {
        $carpetaFisico = Join-Path $CarpetaBackups "fisico_$marca"
        Invoke-Pg (Join-Path $bin 'pg_basebackup.exe') ($conexion + @('-D', $carpetaFisico, '-Ft', '-z', '-X', 'stream', '-P'))
        Write-Log "Backup fisico creado: $carpetaFisico"
    }

    # 4. Rotacion: elimina backups con mas de -DiasRetencion dias
    $limite = (Get-Date).AddDays(-$DiasRetencion)
    $viejos = Get-ChildItem $CarpetaBackups -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match "^($([regex]::Escape($BaseDatos))_|globales_|fisico_)" } |
              Where-Object { $_.LastWriteTime -lt $limite }
    foreach ($v in $viejos) {
        Remove-Item $v.FullName -Recurse -Force
        Write-Log "Rotacion: eliminado $($v.Name)"
    }

    $seg = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Log "===== Backup finalizado correctamente en $seg s ====="
    exit 0
}
catch {
    Write-Log "FALLO EL BACKUP: $($_.Exception.Message)" 'ERROR'
    # Si el dump quedo incompleto o invalido, se elimina para no confundirlo con un backup valido
    if ($dump -and -not $dumpValido -and (Test-Path $dump)) { Remove-Item $dump -Force -ErrorAction SilentlyContinue }
    exit 1
}
