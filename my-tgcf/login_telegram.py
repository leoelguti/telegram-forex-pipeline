import os
import sys
import json

# Ensure we are in the my-tgcf directory
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(BASE_DIR)

from telethon.sync import TelegramClient
from telethon.sessions import StringSession

CONFIG_FILE = os.path.join(BASE_DIR, "tgcf.config.json")

print("=" * 60)
print("     ASISTENTE DE INICIO DE SESION DE TELEGRAM (TGCF)      ")
print("=" * 60)
print("Este asistente te conectara a Telegram y generara el")
print("'Session String' necesario para reenviar senales desde canales VIP.")
print("=" * 60)
print()

# Read existing config if available
config_data = {}
if os.path.exists(CONFIG_FILE):
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            config_data = json.load(f)
    except Exception:
        config_data = {}

prev_api_id = config_data.get("login", {}).get("API_ID", 0)
prev_api_hash = config_data.get("login", {}).get("API_HASH", "")

if prev_api_id and prev_api_id != 0:
    api_id_input = input(f"API ID [{prev_api_id}]: ").strip()
    api_id = int(api_id_input) if api_id_input else prev_api_id
else:
    api_id = int(input("Introduce tu API ID (de my.telegram.org): ").strip())

if prev_api_hash:
    api_hash_input = input(f"API HASH [{prev_api_hash}]: ").strip()
    api_hash = api_hash_input if api_hash_input else prev_api_hash
else:
    api_hash = input("Introduce tu API HASH (de my.telegram.org): ").strip()

print("\nIniciando conexion con los servidores de Telegram...")
print("A continuacion Telegram te pedira:")
print("  1. Tu numero de telefono con codigo de pais (ejemplo: +584121234567 o +34612345678)")
print("  2. El codigo de verificacion que recibiras en tu Telegram oficial")
print("  3. Tu contrasena 2FA (si la tienes activada)\n")

with TelegramClient(StringSession(), api_id, api_hash) as client:
    session_str = client.session.save()
    me = client.get_me()
    first_name = me.first_name if me else "Usuario"
    username = f"@{me.username}" if me and me.username else ""
    
    print("\n" + "=" * 60)
    print(f" INICIO DE SESION EXITOSO! Bienvenido {first_name} {username}")
    print("=" * 60)
    print("\nTu 'Session String' generado es:\n")
    print(session_str)
    print("\n" + "=" * 60)
    
    # Save automatically to tgcf.config.json
    if "login" not in config_data:
        config_data["login"] = {}
        
    config_data["login"]["API_ID"] = api_id
    config_data["login"]["API_HASH"] = api_hash
    config_data["login"]["user_type"] = 1  # 1 = User
    config_data["login"]["SESSION_STRING"] = session_str
    
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config_data, f, indent=2)
        
    print(" Configuracion guardada automaticamente en tgcf.config.json")
    print(" Ya NO necesitas pegarla manualmente en la web si no quieres,")
    print(" pero si refrescas la web http://localhost:8501 ya veras tu sesion cargada.")
    print("=" * 60)

input("\nPresiona ENTER para salir...")
