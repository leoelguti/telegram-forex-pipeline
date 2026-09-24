"""
Script de Pruebas Automatizadas para el Pipeline de Trading Forex (n8n + Groq + PocketBase + MT5)
Ejecuta los 6 casos de prueba esenciales contra el endpoint de n8n en el VPS y reporta los resultados.
"""

import urllib.request
import urllib.error
import json
import sys

# Configurar salida UTF-8 para consola Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

N8N_WEBHOOK_URL = "http://209.145.54.168:5678/webhook/signal"

TEST_CASES = [
    {
        "id": 1,
        "name": "Señal Estándar Forex (EURUSD)",
        "payload": {
            "message": "BUY EURUSD 1.08500 SL 1.08000 TP 1.09500",
            "channel_id": "chan_elitetrad",
            "telegram_msg_id": "test_001"
        },
        "expect_execute": True,
        "expected_symbol": "EURUSD",
        "expected_action": "BUY"
    },
    {
        "id": 2,
        "name": "Materia Prima (GOLD -> XAUUSD) con Múltiples TPs",
        "payload": {
            "message": "[ORIGIN_ID:chan_goldvip0|NAME:Gold Signals VIP] BUY GOLD 2650.00 SL 2640.00 TP1 2660.00 TP2 2670.00 TP3 2685.00",
            "channel_id": "chan_goldvip0",
            "telegram_msg_id": "test_002"
        },
        "expect_execute": True,
        "expected_symbol": "XAUUSD",
        "expected_tps_count": 3
    },
    {
        "id": 3,
        "name": "Publicidad / VIP que contiene Señal Legítima",
        "payload": {
            "message": "👑 VIP SIGNAL FOR ALL 👑 SELL GBPUSD 1.30500 SL 1.31000 TP 1.29800 Join VIP for 50% discount contact @admin",
            "channel_id": "chan_tfxc0000",
            "telegram_msg_id": "test_003"
        },
        "expect_execute": True,
        "expected_symbol": "GBPUSD",
        "expected_action": "SELL"
    },
    {
        "id": 4,
        "name": "Pie de Foto de Análisis Técnico (Trendline Breakout)",
        "payload": {
            "message": "Análisis H4 adjunto con ruptura de tendencia: BUY US30 43500 SL 43350 TP 43800",
            "channel_id": "chan_xauhq000",
            "telegram_msg_id": "test_004"
        },
        "expect_execute": True,
        "expected_symbol": "US30",
        "expected_action": "BUY"
    },
    {
        "id": 5,
        "name": "Descarte de Actualización Informativa (TP HIT / Pips Gained)",
        "payload": {
            "message": "GOLD BUY TP1 HIT! 🔥🔥 +40 PIPS GAINED! Secure profit guys!",
            "channel_id": "chan_freegold",
            "telegram_msg_id": "test_005"
        },
        "expect_execute": False,
        "expected_reason_contains": "Actualiza"
    },
    {
        "id": 6,
        "name": "Rechazo de Riesgo por Incoherencia (BUY con SL por encima de Entrada)",
        "payload": {
            "message": "BUY XAUUSD 2650.00 SL 2670.00 TP 2680.00",
            "channel_id": "chan_goldvip0",
            "telegram_msg_id": "test_006"
        },
        "expect_execute": False,
        "expected_reason_contains": "Incoherencia"
    }
]

def run_tests():
    print("=" * 80)
    print("   🧪 SUITE DE PRUEBAS DEL PIPELINE DE TRADING (n8n + GROQ + MT5)")
    print(f"   Endpoint objetivo: {N8N_WEBHOOK_URL}")
    print("=" * 80)

    passed_count = 0

    for tc in TEST_CASES:
        t_id = tc["id"]
        t_name = tc["name"]
        payload = tc["payload"]
        expect_exec = tc["expect_execute"]

        print(f"\n[PRUEBA {t_id}] {t_name}")
        print(f"  • Mensaje Enviado: \"{payload['message'][:65]}...\"")

        try:
            data = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(
                N8N_WEBHOOK_URL,
                data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                resp_text = resp.read().decode("utf-8")
                try:
                    res_json = json.loads(resp_text)
                except Exception:
                    res_json = {"raw_text": resp_text}

                actual_exec = res_json.get("execute", False)
                print(f"  • HTTP Status: {resp.status}")
                print(f"  • Respuesta n8n: {json.dumps(res_json, ensure_ascii=False)}")

                success = False
                if actual_exec == expect_exec:
                    if expect_exec:
                        # Validar símbolo si aplica
                        sym_ok = tc.get("expected_symbol") is None or res_json.get("symbol") == tc.get("expected_symbol")
                        act_ok = tc.get("expected_action") is None or res_json.get("action") == tc.get("expected_action")
                        tps_ok = tc.get("expected_tps_count") is None or len(res_json.get("take_profits", [])) == tc.get("expected_tps_count")
                        if sym_ok and act_ok and tps_ok:
                            success = True
                    else:
                        reason = res_json.get("reason", "")
                        r_contains = tc.get("expected_reason_contains", "")
                        if not r_contains or r_contains.lower() in reason.lower():
                            success = True

                if success:
                    print(f"  --> RESULTADO: 🟢 APROBADA")
                    passed_count += 1
                else:
                    print(f"  --> RESULTADO: 🔴 FALLÓ (Se esperaba execute={expect_exec})")

        except urllib.error.HTTPError as e:
            print(f"  • HTTP Error {e.code}: {e.read().decode('utf-8')}")
            print(f"  --> RESULTADO: 🔴 ERROR HTTP")
        except Exception as e:
            print(f"  • Excepción: {e}")
            print(f"  --> RESULTADO: 🔴 EXCEPCIÓN")

    print("\n" + "=" * 80)
    print(f"   RESUMEN FINAL: {passed_count} / {len(TEST_CASES)} Pruebas Aprobadas")
    print("=" * 80)

if __name__ == "__main__":
    run_tests()
