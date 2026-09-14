import urllib.request
import json

payload = json.dumps({
    "message": "BUY GOLD NOW SL 3440 TP 3454",
    "channel_id": "-1003984394749",
    "telegram_msg_id": "4"
}).encode('utf-8')

url = 'http://127.0.0.1:5678/webhook/signal'
try:
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})
    resp = urllib.request.urlopen(req, timeout=10)
    data = resp.read().decode('utf-8')
    print(f"Status: {resp.getcode()}")
    print(f"Response: {data}")
except Exception as e:
    print(f"Error: {e}")
