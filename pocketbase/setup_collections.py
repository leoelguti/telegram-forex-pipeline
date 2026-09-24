import requests
import json

BASE_URL = "http://127.0.0.1:8090"

# 1. Login as superuser
auth_resp = requests.post(
    f"{BASE_URL}/api/collections/_superusers/auth-with-password",
    json={"identity": "admin@tradingforex.local", "password": "admin123456"}
)
auth_resp.raise_for_status()
token = auth_resp.json()["token"]
headers = {"Authorization": token, "Content-Type": "application/json"}

# Define collections
collections = [
    {
        "name": "canales_fuente",
        "type": "base",
        "listRule": "",
        "viewRule": "",
        "createRule": "",
        "updateRule": "",
        "deleteRule": "",
        "fields": [
            {"name": "nombre", "type": "text", "required": True},
            {"name": "channel_id", "type": "text", "required": True},
            {"name": "estado", "type": "select", "values": ["activo", "pausado"], "maxSelect": 1},
            {"name": "riesgo_default", "type": "number"}
        ]
    },
    {
        "name": "logs_mensajes",
        "type": "base",
        "listRule": "",
        "viewRule": "",
        "createRule": "",
        "updateRule": "",
        "deleteRule": "",
        "fields": [
            {"name": "canal_id", "type": "text", "required": False},
            {"name": "telegram_msg_id", "type": "text", "required": False},
            {"name": "mensaje_crudo", "type": "text", "required": False},
            {"name": "json_extraido", "type": "json", "required": False},
            {
                "name": "estado",
                "type": "select",
                "values": ["DESCARTADO", "ERROR_PARSER", "RECHAZO_RIESGO", "ENVIADO_MT5"],
                "maxSelect": 1
            }
        ]
    },
    {
        "name": "trades_metricas",
        "type": "base",
        "listRule": "",
        "viewRule": "",
        "createRule": "",
        "updateRule": "",
        "deleteRule": "",
        "fields": [
            {"name": "ticket_mt5", "type": "text", "required": False},
            {"name": "canal_id", "type": "text", "required": False},
            {"name": "par", "type": "text", "required": False},
            {"name": "accion", "type": "select", "values": ["BUY", "SELL", "LONG", "SHORT"], "maxSelect": 1},
            {"name": "lotaje", "type": "number"},
            {"name": "precio_entrada", "type": "number"},
            {"name": "stop_loss", "type": "number"},
            {"name": "take_profit", "type": "number"},
            {"name": "precio_cierre", "type": "number"},
            {"name": "profit_usd", "type": "number"},
            {"name": "pips", "type": "number"},
            {"name": "estado_trade", "type": "select", "values": ["ABIERTO", "CERRADO"], "maxSelect": 1}
        ]
    }
]

# Fetch existing collections
existing = {c["name"]: c["id"] for c in requests.get(f"{BASE_URL}/api/collections", headers=headers).json().get("items", [])}

for col in collections:
    name = col["name"]
    if name in existing:
        print(f"Collection '{name}' already exists.")
    else:
        resp = requests.post(f"{BASE_URL}/api/collections", headers=headers, json=col)
        if resp.status_code in (200, 201):
            print(f"Collection '{name}' created successfully.")
        else:
            print(f"Error creating '{name}': {resp.status_code} - {resp.text}")
