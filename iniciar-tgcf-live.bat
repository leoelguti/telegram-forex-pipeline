@echo off
title TGCF Live - Reenvio de Senales Forex
cd /d "%~dp0my-tgcf"
call .venv\Scripts\activate.bat
echo ========================================================
echo       TGCF LIVE - REENVIO DE SENALES TELEGRAM
echo ========================================================
echo Canales origen monitoreados (5):
echo   [1] EliteTradingSignals       (@elitetrading_signals)
echo   [2] XAUHQ                    (ID: -1001207746934)
echo   [3] TFXC SIGNALS             (@TFXCTrader)
echo   [4] FreeGoldPrincessSignals  (ID: -1002045626433)
echo   [5] Gold Signals VIP         (ID: -1001868019139)
echo.
echo Canal destino: Senales MT5 Forex (https://t.me/+G-9R9xrPIEwxMThh)
echo.
echo Para detener el reenvio, simplemente cierra esta ventana.
echo ========================================================
echo.
tgcf --loud live
pause
