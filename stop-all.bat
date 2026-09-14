@echo off
title Detener - Trading Forex Pipeline
echo ========================================================
echo       Deteniendo Servicios de Trading Forex
echo ========================================================
echo.

echo Deteniendo PocketBase...
taskkill /f /im pocketbase.exe 2>nul

echo Deteniendo procesos de n8n / Node en puerto 5678...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":5678" ^| findstr "LISTENING"') do taskkill /f /pid %%a 2>nul

echo Deteniendo procesos de tgcf en puerto 8501...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8501" ^| findstr "LISTENING"') do taskkill /f /pid %%a 2>nul

echo.
echo ========================================================
echo   Servicios detenidos con exito.
echo ========================================================
pause
