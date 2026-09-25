#!/usr/bin/env bash
# ==============================================================================
# Script de actualización rápida en VPS Ubuntu
# Aplica los cambios de tgcf, web UI, n8n workflow y reinicia los servicios
# ==============================================================================

set -e

PROJECT_DIR="/opt/trading-forex-pipeline"
cd "$PROJECT_DIR"

echo "========================================================"
echo "    ACTUALIZANDO PIPELINE DE TRADING EN VPS"
echo "========================================================"

BASE_URL="https://raw.githubusercontent.com/leoelguti/telegram-forex-pipeline/main"

# 1. Descargar archivos de tgcf y web UI actualizados directamente
echo "[1/4] Descargando últimas actualizaciones desde GitHub..."
mkdir -p "$PROJECT_DIR/my-tgcf/tgcf/web_ui/pages"

curl -fsSL "$BASE_URL/my-tgcf/tgcf/config.py" -o "$PROJECT_DIR/my-tgcf/tgcf/config.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/live.py" -o "$PROJECT_DIR/my-tgcf/tgcf/live.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/utils.py" -o "$PROJECT_DIR/my-tgcf/tgcf/utils.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/web_ui/run.py" -o "$PROJECT_DIR/my-tgcf/tgcf/web_ui/run.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/web_ui/0_%F0%9F%91%8B_Hello.py" -o "$PROJECT_DIR/my-tgcf/tgcf/web_ui/0_👋_Hello.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/web_ui/pages/3_%F0%9F%94%97_Connections.py" -o "$PROJECT_DIR/my-tgcf/tgcf/web_ui/pages/3_🔗_Connections.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/web_ui/pages/5_%F0%9F%8F%83_Run.py" -o "$PROJECT_DIR/my-tgcf/tgcf/web_ui/pages/5_🏃_Run.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/web_ui/pages/6_%F0%9F%93%8A_Analytics.py" -o "$PROJECT_DIR/my-tgcf/tgcf/web_ui/pages/6_📊_Analytics.py" || true
curl -fsSL "$BASE_URL/my-tgcf/tgcf/web_ui/pages/7_%F0%9F%94%AC_Advanced.py" -o "$PROJECT_DIR/my-tgcf/tgcf/web_ui/pages/7_🔬_Advanced.py" || true

# Eliminar archivo antiguo de Advanced para no duplicar numeración
rm -f "$PROJECT_DIR/my-tgcf/tgcf/web_ui/pages/6_🔬_Advanced.py" 2>/dev/null || true

# Descargar workflow n8n y script de auditoría CLI
curl -fsSL "$BASE_URL/n8n/workflow_forex_signal_pipeline.json" -o "$PROJECT_DIR/n8n/workflow_forex_signal_pipeline.json" || true
curl -fsSL "$BASE_URL/audit_ranking_canales.py" -o "$PROJECT_DIR/audit_ranking_canales.py" || true
chmod +x "$PROJECT_DIR/audit_ranking_canales.py" 2>/dev/null || true

# 2. Ajustar permisos
echo "[2/4] Ajustando permisos de archivos..."
chown -R root:root "$PROJECT_DIR" 2>/dev/null || true

# 3. Reiniciar servicios de tgcf (sin tocar n8n para preservar credenciales)
echo "[3/3] Reiniciando servicios tgcf y tgcf-web..."
systemctl restart tgcf.service || true
systemctl restart tgcf-web.service 2>/dev/null || true

sleep 2

echo ""
echo "========================================================"
echo "  ¡ACTUALIZACION COMPLETADA CON EXITO!"
echo "========================================================"
systemctl is-active tgcf.service && echo "  - tgcf (Reenvio + Filtro Anti-Spam): 🟢 ACTIVO"
systemctl is-active tgcf-web.service && echo "  - tgcf-web (Panel Visual + Analytics): 🟢 ACTIVO"
systemctl is-active n8n.service && echo "  - n8n (Orquestador Multi-TP):        🟢 ACTIVO"
systemctl is-active pocketbase.service && echo "  - PocketBase (Base de Datos):        🟢 ACTIVO"
echo "========================================================"
