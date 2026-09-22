# ==============================================================================
# Script para sincronizar el proyecto desde Windows hacia tu VPS Ubuntu
# ==============================================================================

param (
    [string]$VpsUser = "root",
    [string]$VpsHost = "",
    [string]$RemoteDir = "/opt/trading-forex-pipeline"
)

Clear-Host
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "    SINCRONIZADOR DE ARCHIVOS HACIA VPS UBUNTU          " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $VpsHost) {
    $VpsHost = Read-Host "Introduce la IP de tu VPS (ej: 147.182.123.45)"
}
if (-not $VpsHost) {
    Write-Host "[ERROR] Debes proporcionar la IP de tu VPS." -ForegroundColor Red
    exit 1
}

$confirmUser = Read-Host "Usuario SSH [$VpsUser]"
if ($confirmUser) {
    $VpsUser = $confirmUser
}

$confirmDir = Read-Host "Directorio remoto en VPS [$RemoteDir]"
if ($confirmDir) {
    $RemoteDir = $confirmDir
}

$LocalRoot = (Get-Item "$PSScriptRoot\..").FullName
Write-Host ""
Write-Host "Origen local:  $LocalRoot" -ForegroundColor Yellow
Write-Host "Destino VPS:   $VpsUser@$VpsHost:$RemoteDir" -ForegroundColor Yellow
Write-Host ""

# 1. Crear directorio remoto si no existe
Write-Host "[1/3] Creando carpeta en el VPS..." -ForegroundColor Green
ssh -o StrictHostKeyChecking=accept-new "$VpsUser@$VpsHost" "mkdir -p $RemoteDir"

# 2. Empaquetar y transferir archivos clave
Write-Host "[2/3] Transfiriendo archivos de configuracion y codigo..." -ForegroundColor Green

# Usar tar a traves de ssh para una transferencia rapida, limpia y preservando permisos
$excludeList = @(
    "--exclude=.venv",
    "--exclude=.git",
    "--exclude=*.zip",
    "--exclude=*.log",
    "--exclude=mt5_portable.zip",
    "--exclude=mql5",
    "--exclude=__pycache__"
)

Set-Location $LocalRoot
$tarArgs = @("-czf", "-", "--exclude=.venv", "--exclude=.git", "--exclude=*.zip", "--exclude=*.log", "--exclude=mt5_portable.zip", "--exclude=__pycache__", ".")
& tar $tarArgs | ssh "$VpsUser@$VpsHost" "tar -xzf - -C $RemoteDir"

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Archivos sincronizados exitosamente." -ForegroundColor Green
} else {
    Write-Host "[AVISO] Si fallo tar, intentando copia directa con scp..." -ForegroundColor Yellow
    scp -r "$LocalRoot/my-tgcf" "$LocalRoot/pocketbase" "$LocalRoot/n8n" "$LocalRoot/vps" "$VpsUser@$VpsHost:$RemoteDir/"
}

# 3. Dar permisos de ejecucion al instalador
Write-Host "[3/3] Asignando permisos de ejecucion en el VPS..." -ForegroundColor Green
ssh "$VpsUser@$VpsHost" "chmod +x $RemoteDir/vps/deploy-vps.sh"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  SINCRONIZACION COMPLETADA!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Para desplegar o actualizar los servicios en tu VPS, ejecuta:" -ForegroundColor White
Write-Host "  ssh $VpsUser@$VpsHost" -ForegroundColor Yellow
Write-Host "  cd $RemoteDir/vps" -ForegroundColor Yellow
Write-Host "  sudo ./deploy-vps.sh" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
pause
