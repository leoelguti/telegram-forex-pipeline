import os
import zipfile
import shutil

print("Creando paquete portátil de MetaTrader 5 para el VPS...")

mt5_install = r"C:\Program Files\MetaTrader 5"
mt5_data = r"C:\Users\yvana_ec6wrqe\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5"
zip_output = r"C:\Users\yvana_ec6wrqe\OneDrive\Documents\PASANTIAS\TRADING FOREX\mt5_portable.zip"

files_added = 0
with zipfile.ZipFile(zip_output, 'w', zipfile.ZIP_DEFLATED) as zf:
    # 1. Add base MT5 files
    for root, dirs, files in os.walk(mt5_install):
        for file in files:
            # Skip uninstaller to save space
            if file.lower() in ['uninstall.exe']:
                continue
            abs_path = os.path.join(root, file)
            rel_path = os.path.relpath(abs_path, mt5_install)
            zf.write(abs_path, arcname=os.path.join("MetaTrader5", rel_path))
            files_added += 1

    # 2. Add MQL5 folder with compiled Service, EA, and Includes
    if os.path.exists(mt5_data):
        for root, dirs, files in os.walk(mt5_data):
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.path.relpath(abs_path, mt5_data)
                zf.write(abs_path, arcname=os.path.join("MetaTrader5", "MQL5", rel_path))
                files_added += 1

    # 3. Add launch script for Ubuntu Wine
    run_script = """#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
wine terminal64.exe /portable
"""
    zf.writestr(os.path.join("MetaTrader5", "run_mt5.sh"), run_script)

zip_size_mb = os.path.getsize(zip_output) / (1024 * 1024)
print(f"¡Listo! Archivo creado exitosamente:")
print(f"Ruta: {zip_output}")
print(f"Archivos empaquetados: {files_added}")
print(f"Tamaño comprimido: {zip_size_mb:.2f} MB")
