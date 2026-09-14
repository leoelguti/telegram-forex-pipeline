@echo off
title TGCF Live - Reenvio de Senales Forex
cd /d "%~dp0my-tgcf"
call .venv\Scripts\activate.bat
echo ========================================================
echo       TGCF LIVE - REENVIO DE SENALES TELEGRAM
echo ========================================================
echo.
echo Monitoreando canal origen: https://t.me/elitetrading_signals
echo Reenviando a canal destino: https://t.me/+G-9R9xrPIEwxMThh
echo.
echo Para detener el reenvio, simplemente cierra esta ventana.
echo ========================================================
echo.
tgcf --loud live
pause
