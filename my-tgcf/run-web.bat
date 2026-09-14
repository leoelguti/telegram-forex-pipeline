@echo off
cd /d "%~dp0"
call .venv\Scripts\activate.bat
echo Iniciando interfaz web de tgcf...
echo Por defecto la contrasena es: tgcf
echo Accede en tu navegador a: http://localhost:8501
tgcf-web
pause
