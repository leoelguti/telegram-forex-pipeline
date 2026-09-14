import sqlite3
import json

db_path = 'n8n/.n8n/.n8n/database.sqlite'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("SELECT connections FROM workflow_entity WHERE id = '6vqAZMbw2e8cxpaD'")
conn_data = json.loads(c.fetchone()[0])
print(json.dumps(conn_data, indent=2))
conn.close()
