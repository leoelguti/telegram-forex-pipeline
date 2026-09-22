@echo off
title Sincronizar Proyecto con VPS Ubuntu
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-to-vps.ps1"
pause
