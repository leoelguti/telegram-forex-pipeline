@echo off
title Launcher - Trading Forex Pipeline
cd /d "%~dp0"

echo ========================================================
echo       Iniciando Pipeline de Trading Forex
echo ========================================================
echo.

echo [1/3] Iniciando PocketBase (Puerto 8090)...
if not exist "%~dp0pocketbase\pocketbase.exe" (
    echo [INFO] pocketbase.exe no encontrado. Descargando automaticamente...
    call "%~dp0pocketbase\download_pocketbase.bat"
)
start "PocketBase - Trading Forex" /d "%~dp0pocketbase" cmd /k "pocketbase.exe serve --http=127.0.0.1:8090"

echo [2/3] Iniciando n8n (Puerto 5678)...
start "n8n - Trading Forex" /d "%~dp0n8n" cmd /k "run-n8n.bat"

echo [3/3] Iniciando tgcf en modo LIVE (Reenvio en tiempo real)...
start "tgcf Live - Trading Forex" /d "%~dp0my-tgcf" cmd /k "call .venv\Scripts\activate.bat && tgcf --loud live"

echo.
echo ========================================================
echo   Servicios lanzados en ventanas independientes:
echo   - PocketBase:  http://127.0.0.1:8090/_/
echo   - n8n:         http://127.0.0.1:5678
echo   - tgcf Live:   Reenviando senales en tiempo real
echo ========================================================
echo.
timeout /t 5
