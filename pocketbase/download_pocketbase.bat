@echo off
title Descargando PocketBase
cd /d "%~dp0"

if exist pocketbase.exe (
    echo [INFO] pocketbase.exe ya existe en este directorio.
    goto end
)

echo ========================================================
echo   Descargando PocketBase (v0.25.9 para Windows x64)...
echo ========================================================

powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/pocketbase/pocketbase/releases/download/v0.25.9/pocketbase_0.25.9_windows_amd64.zip' -OutFile 'pb_temp.zip'"

if not exist pb_temp.zip (
    echo [ERROR] No se pudo descargar PocketBase. Por favor descargalo manualmente desde:
    echo https://pocketbase.io/docs/
    pause
    exit /b 1
)

echo Descomprimiendo PocketBase...
powershell -Command "Expand-Archive -Path 'pb_temp.zip' -DestinationPath . -Force"
del /f /q pb_temp.zip

echo [OK] PocketBase instalado con exito en %~dp0pocketbase.exe

:end
echo Listo.
timeout /t 3
