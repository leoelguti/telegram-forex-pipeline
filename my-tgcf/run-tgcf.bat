@echo off
cd /d "%~dp0"
call .venv\Scripts\activate.bat
echo ========================================================
echo                 TGCF - Telegram Forwarder
echo ========================================================
echo Seleccione el modo de ejecucion:
echo 1) Live (reenvio continuo en tiempo real)
echo 2) Past (reenvio de historial de mensajes antiguos)
echo.
set /p mode="Elige una opcion (1 o 2): "
if "%mode%"=="1" (
    tgcf live
) else if "%mode%"=="2" (
    tgcf past
) else (
    echo Opcion invalida.
)
pause
