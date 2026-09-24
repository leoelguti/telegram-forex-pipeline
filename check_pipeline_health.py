import urllib.request
import json
import time
import sys

# Force UTF-8 output
sys.stdout.reconfigure(encoding='utf-8')

VPS_IP = '209.145.54.168'
print("=" * 60)
print("     INFORME DE SALUD Y TELEMETRIA DEL PIPELINE FOREX      ")
print("=" * 60)
print(f"VPS Endpoint: http://{VPS_IP}\n")

# 1. PocketBase Health
pb_url = f"http://{VPS_IP}:8090/api/health"
try:
    with urllib.request.urlopen(pb_url, timeout=5) as r:
        print(f"[1/4] PocketBase Server: 🟢 ONLINE (Status {r.status})")
except Exception as e:
    print(f"[1/4] PocketBase Server: 🔴 FALLO ({e})")

# 2. Canales Fuente Registrados
channels_url = f"http://{VPS_IP}:8090/api/collections/canales_fuente/records"
try:
    with urllib.request.urlopen(channels_url, timeout=5) as r:
        data = json.loads(r.read().decode())
        items = data.get("items", [])
        print(f"[2/4] Canales Fuente Configurados: 🟢 {len(items)} canales activos")
        for c in items:
            print(f"      • {c.get('nombre')}: {c.get('channel_id')} ({c.get('estado')})")
except Exception as e:
    print(f"[2/4] Canales Fuente: 🔴 ERROR ({e})")

# 3. Test de Señal en Vivo hacia n8n + Groq (con Metadatos de Origen y Accion LONG)
n8n_url = f"http://{VPS_IP}:5678/webhook/signal"
test_signal = {
    "message": "LONG EURUSD 1.0850 SL 1.0800 TP 1.0950\n\n[ORIGIN_ID:-1001662267019|NAME:EliteTradingSignals]",
    "channel_id": "-1003984394749",
    "telegram_msg_id": str(int(time.time()))
}
req = urllib.request.Request(n8n_url, data=json.dumps(test_signal).encode(), headers={"Content-Type": "application/json"})
try:
    start_t = time.time()
    with urllib.request.urlopen(req, timeout=12) as r:
        elapsed_ms = int((time.time() - start_t) * 1000)
        resp_data = r.read().decode()
        print(f"\n[3/4] Inferencia n8n + Groq Cloud: 🟢 EXITO (Status {r.status} en {elapsed_ms}ms)")
        try:
            parsed_resp = json.loads(resp_data)
            print(f"      • Ejecutar: {parsed_resp.get('execute')}")
            print(f"      • Par: {parsed_resp.get('symbol')} | Accion: {parsed_resp.get('action')}")
            print(f"      • Entrada: {parsed_resp.get('entry')} | SL: {parsed_resp.get('stop_loss')} | TP: {parsed_resp.get('take_profit')}")
            if parsed_resp.get('comment'):
                print(f"      • Comentario MT5: '{parsed_resp.get('comment')}'")
            if parsed_resp.get('channel_id'):
                print(f"      • Canal Origen Atribuido: {parsed_resp.get('channel_id')} ({parsed_resp.get('channel_name')})")
        except Exception:
            print(f"      • Respuesta en crudo: {resp_data}")
except urllib.error.HTTPError as e:
    print(f"\n[3/4] Inferencia n8n + Groq: 🔴 HTTP {e.code}: {e.read().decode()}")
except Exception as e:
    print(f"\n[3/4] Inferencia n8n + Groq: 🔴 ERROR: {e}")

# 4. Auditoria de Logs en PocketBase
logs_url = f"http://{VPS_IP}:8090/api/collections/logs_mensajes/records?perPage=50"
try:
    with urllib.request.urlopen(logs_url, timeout=5) as r:
        logs_data = json.loads(r.read().decode())
        items = logs_data.get("items", [])
        total = logs_data.get("totalItems", 0)
        print(f"\n[4/4] Auditoria PocketBase (logs_mensajes): 🟢 {total} registros totales")
        print("      Ultimos eventos registrados:")
        for item in items[-4:]:
            msg = item.get("mensaje_crudo", "")
            est = item.get("estado", "")
            print(f"      • {est:15} | \"{msg}\"")
except Exception as e:
    print(f"\n[4/4] Auditoria PocketBase: 🔴 ERROR ({e})")

print("\n" + "=" * 60)
