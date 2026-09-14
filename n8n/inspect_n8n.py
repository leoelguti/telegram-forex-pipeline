import sqlite3

db_path = r"C:\Users\yvana_ec6wrqe\OneDrive\Documents\PASANTIAS\TRADING FOREX\n8n\.n8n\.n8n\database.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
print("Tables:", tables)

for t in ["workflow_entity", "workflow_published_version", "webhook_entity"]:
    res = cur.execute(f"SELECT sql FROM sqlite_master WHERE name='{t}'").fetchone()
    print(f"Schema of {t}:", res[0] if res else "Not found")
