@echo off
cd /d "%~dp0"
echo ========================================================
echo                 n8n - Orquestador de Trading
echo ========================================================

:: Cargar variables de entorno desde .env si existe
if exist .env (
    for /f "usebackq tokens=1* delims==" %%A in (`findstr /v "^#" .env ^| findstr /v "^$"`) do (
        set "%%A=%%B"
    )
)

set N8N_PORT=5678
set N8N_HOST=127.0.0.1
set N8N_LISTEN_ADDRESS=127.0.0.1
set WEBHOOK_URL=http://127.0.0.1:5678/
set N8N_USER_FOLDER=%~dp0.n8n
set N8N_DIAGNOSTICS_ENABLED=false
set N8N_METRICS=false

echo n8n iniciando en: http://127.0.0.1:5678
echo Carpeta de datos: %N8N_USER_FOLDER%
echo.
call "C:\Users\yvana_ec6wrqe\AppData\Roaming\npm\n8n.cmd" start
pause

