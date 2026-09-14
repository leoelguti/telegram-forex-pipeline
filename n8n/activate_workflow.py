import sqlite3
import json

db_path = r"C:\Users\yvana_ec6wrqe\OneDrive\Documents\PASANTIAS\TRADING FOREX\n8n\.n8n\.n8n\database.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

with open(r"C:\Users\yvana_ec6wrqe\OneDrive\Documents\PASANTIAS\TRADING FOREX\n8n\workflow_forex_signal_pipeline.json", "r", encoding="utf-8") as f:
    wf = json.load(f)

nodes_json = json.dumps(wf["nodes"])
connections_json = json.dumps(wf["connections"])

# 1. Update workflow_entity
cur.execute("""
UPDATE workflow_entity
SET active = 1, triggerCount = 1, nodes = ?, connections = ?
WHERE id = '6vqAZMbw2e8cxpaD'
""", (nodes_json, connections_json))

# 2. Update workflow_history
cur.execute("""
UPDATE workflow_history
SET nodes = ?, connections = ?
WHERE workflowId = '6vqAZMbw2e8cxpaD'
""", (nodes_json, connections_json))

# 3. Ensure webhook_entity
cur.execute("""
INSERT OR REPLACE INTO webhook_entity (workflowId, webhookPath, method, node, webhookId, pathLength)
VALUES ('6vqAZMbw2e8cxpaD', 'signal', 'POST', 'Webhook MT5', 'signal', 1)
""")

conn.commit()
print("Workflow synced with updated Groq model.")
