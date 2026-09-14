import urllib.request
import json

payload = json.dumps({
    "message": "BUY GOLD 2650.00 SL 2640.00 TP 2670.00",
    "channel_id": "TEST_CHANNEL",
    "msg_id": "999"
}).encode('utf-8')

for url in ['http://127.0.0.1:5678/webhook/signal', 'http://127.0.0.1:5678/webhook-test/signal']:
    try:
        req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})
        resp = urllib.request.urlopen(req)
        print(f"SUCCESS {url}: Status {resp.getcode()} -> {resp.read().decode('utf-8')}")
    except urllib.error.HTTPError as e:
        print(f"HTTPError {url}: {e.code} -> {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"Error {url}: {e}")
