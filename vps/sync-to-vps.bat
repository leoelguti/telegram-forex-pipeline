@echo off
setlocal EnableDelayedExpansion
title Sincronizar Proyecto con VPS Ubuntu
cd /d "%~dp0.."

echo ========================================================
echo       SINCRONIZAR PROYECTO HACIA VPS UBUNTU
echo ========================================================
echo.

:: 1. Empaquetar archivos con Python
if exist "my-tgcf\.venv\Scripts\python.exe" (
    "my-tgcf\.venv\Scripts\python.exe" "vps\make_bundle.py"
) else (
    python "vps\make_bundle.py"
)

if not exist "vps\bundle_vps.tar.gz" (
    echo.
    echo [ERROR] No se pudo crear el paquete vps\bundle_vps.tar.gz
    pause
    exit /b 1
)

echo.
echo --------------------------------------------------------
set /p VPS_HOST="Introduce la IP de tu VPS Ubuntu: "
if "%VPS_HOST%"=="" (
    echo [ERROR] La IP del VPS no puede estar vacia.
    pause
    exit /b 1
)

set /p VPS_USER="Usuario SSH [presiona Enter para 'root']: "
if "%VPS_USER%"=="" set VPS_USER=root

set /p VPS_PORT="Puerto SSH [presiona Enter para '22']: "
if "%VPS_PORT%"=="" set VPS_PORT=22

set /p REMOTE_DIR="Directorio en el VPS [presiona Enter para '/opt/trading-forex-pipeline']: "
if "%REMOTE_DIR%"=="" set REMOTE_DIR=/opt/trading-forex-pipeline

echo --------------------------------------------------------
echo.
echo [1/2] Subiendo paquete al VPS (%VPS_USER%@%VPS_HOST%:%VPS_PORT%)...
echo *(Si tu VPS pide contrasena, ingresala a continuacion)*
echo.

scp -P %VPS_PORT% -o StrictHostKeyChecking=accept-new "vps\bundle_vps.tar.gz" "%VPS_USER%@%VPS_HOST%:/tmp/bundle_vps.tar.gz"
if errorlevel 1 (
    echo.
    echo [ERROR] Fallo la transferencia por scp. Verifica la IP, usuario y contrasena/llave SSH.
    pause
    exit /b 1
)

echo.
echo [2/2] Descomprimiendo en %REMOTE_DIR%...
ssh -p %VPS_PORT% -o StrictHostKeyChecking=accept-new "%VPS_USER%@%VPS_HOST%" "mkdir -p %REMOTE_DIR% && tar -xzf /tmp/bundle_vps.tar.gz -C %REMOTE_DIR% && rm -f /tmp/bundle_vps.tar.gz && chmod +x %REMOTE_DIR%/vps/*.sh"
if errorlevel 1 (
    echo.
    echo [ERROR] Fallo al descomprimir en el VPS.
    pause
    exit /b 1
)

echo.
echo ========================================================
echo       SINCRONIZACION COMPLETADA CON EXITO!
echo ========================================================
echo.
echo Tus archivos ya estan actualizados en: %REMOTE_DIR%
echo.
echo Para aplicar todos los cambios en tu VPS:
echo   1. Conectate por SSH a tu VPS:
echo      ssh -p %VPS_PORT% %VPS_USER%@%VPS_HOST%
echo.
echo   2. Ejecuta el script de actualizacion rapida:
echo      bash %REMOTE_DIR%/vps/update_pipeline_vps.sh
echo.
echo ========================================================
pause
