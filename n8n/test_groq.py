import os
import requests

key = os.getenv("GROQ_API_KEY", "")
if not key:
    print("[AVISO] Define la variable de entorno GROQ_API_KEY o colocala en el archivo .env")
    exit(1)

models_to_test = ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b", "groq/compound-mini"]

system_prompt = """You are a specialized forex trading signal parser. Extract signal details into strict JSON:
{
  "is_signal": boolean,
  "action": "BUY" | "SELL" | null,
  "symbol": string | null (standard broker symbol e.g. XAUUSD, EURUSD. If GOLD return XAUUSD),
  "entry": number | null,
  "stop_loss": number | null,
  "take_profit": number | null,
  "notes": string
}
If not an actionable trade signal, set is_signal=false."""

message = "BUY GOLD 2650.50 SL 2640.00 TP 2670.00"

for m in models_to_test:
    payload = {
        "model": m,
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": message}
        ]
    }
    resp = requests.post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json=payload
    )
    print(f"Model: {m} -> Status: {resp.status_code}")
    if resp.status_code == 200:
        print("Extracted JSON:", resp.json()["choices"][0]["message"]["content"])
        break
    else:
        print("Error:", resp.text[:200])
