# ==============================================================================
# Script para sincronizar el proyecto desde Windows hacia tu VPS Ubuntu
# ==============================================================================

param (
    [string]$VpsUser = "root",
    [string]$VpsHost = "",
    [int]$VpsPort = 22,
    [string]$RemoteDir = "/opt/trading-forex-pipeline"
)

Clear-Host
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "    SINCRONIZADOR DE ARCHIVOS HACIA VPS UBUNTU          " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$localRoot = (Get-Item "$scriptDir\..").FullName

# 1. Empaquetar
$pyPath = "$localRoot\my-tgcf\.venv\Scripts\python.exe"
if (-not (Test-Path $pyPath)) {
    $pyPath = "python"
}

& $pyPath "$scriptDir\make_bundle.py"
$bundleFile = "$scriptDir\bundle_vps.tar.gz"

if (-not (Test-Path $bundleFile)) {
    Write-Host "[ERROR] No se encontro el archivo $bundleFile" -ForegroundColor Red
    pause
    exit 1
}

# 2. Solicitar datos de conexion si no vienen por parametro
if (-not $VpsHost) {
    $VpsHost = Read-Host "Introduce la IP de tu VPS Ubuntu"
}
if (-not $VpsHost) {
    Write-Host "[ERROR] Debes proporcionar la IP de tu VPS." -ForegroundColor Red
    pause
    exit 1
}

$inputUser = Read-Host "Usuario SSH [$VpsUser]"
if ($inputUser) { $VpsUser = $inputUser }

$inputPort = Read-Host "Puerto SSH [$VpsPort]"
if ($inputPort) { $VpsPort = [int]$inputPort }

$inputDir = Read-Host "Directorio remoto en VPS [$RemoteDir]"
if ($inputDir) { $RemoteDir = $inputDir }

Write-Host ""
Write-Host "Subiendo paquete ($bundleFile) a $VpsUser@$VpsHost:$VpsPort..." -ForegroundColor Yellow
Write-Host "*(Si tu VPS pide contrasena, ingresala a continuacion)*" -ForegroundColor Gray
Write-Host ""

# 3. Subir archivo comprimido unico con scp
& scp -P $VpsPort -o StrictHostKeyChecking=accept-new $bundleFile "$VpsUser@${VpsHost}:/tmp/bundle_vps.tar.gz"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo la copia mediante scp." -ForegroundColor Red
    pause
    exit 1
}

# 4. Descomprimir en el VPS
Write-Host "Descomprimiendo en el VPS ($RemoteDir)..." -ForegroundColor Yellow
$remoteCmd = "mkdir -p $RemoteDir && tar -xzf /tmp/bundle_vps.tar.gz -C $RemoteDir && rm -f /tmp/bundle_vps.tar.gz && chmod +x $RemoteDir/vps/*.sh"
& ssh -p $VpsPort -o StrictHostKeyChecking=accept-new "$VpsUser@$VpsHost" $remoteCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  SINCRONIZACION COMPLETADA CON EXITO!" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "Tus archivos estan actualizados en: $RemoteDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Para aplicar todos los cambios en tu VPS:" -ForegroundColor White
    Write-Host "  ssh -p $VpsPort $VpsUser@$VpsHost" -ForegroundColor Yellow
    Write-Host "  bash $RemoteDir/vps/update_pipeline_vps.sh" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
} else {
    Write-Host "[ERROR] Fallo la extraccion en el VPS." -ForegroundColor Red
}

Write-Host ""
pause
