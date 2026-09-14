@echo off
cd /d "%~dp0"
echo ========================================================
echo                 PocketBase - Trading Forex
echo ========================================================
echo Servidor en:  http://127.0.0.1:8090
echo Panel Admin:  http://127.0.0.1:8090/_/
echo Superusuario: admin@tradingforex.local
echo.
pocketbase.exe serve --http="127.0.0.1:8090"
pause
