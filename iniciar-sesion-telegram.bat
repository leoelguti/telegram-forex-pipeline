@echo off
title Iniciar Sesion en Telegram - TGCF
cd /d "%~dp0my-tgcf"
call .venv\Scripts\activate.bat
python login_telegram.py
pause
