#!/usr/bin/env bash
# ==============================================================================
# Script de actualización rápida en VPS Ubuntu
# Aplica los cambios de tgcf, n8n workflow y reinicia los servicios
# ==============================================================================

set -e

PROJECT_DIR="/opt/trading-forex-pipeline"
cd "$PROJECT_DIR"

echo "========================================================"
echo "    ACTUALIZANDO PIPELINE DE TRADING EN VPS"
echo "========================================================"

# 1. Asegurar permisos
echo "[1/4] Ajustando permisos de archivos..."
chown -R root:root "$PROJECT_DIR" 2>/dev/null || true

# 2. Detener n8n temporalmente para liberar bloqueo de base de datos SQLite
echo "[2/4] Preparando base de datos de n8n..."
systemctl stop n8n.service || true

# 3. Importar workflow actualizado en n8n
echo "[3/4] Importando nuevo workflow en n8n..."
export N8N_USER_FOLDER="$PROJECT_DIR/n8n/.n8n"
if command -v n8n &> /dev/null; then
    n8n import:workflow --input="$PROJECT_DIR/n8n/workflow_forex_signal_pipeline.json"
    n8n update:workflow --all --active=true
    echo "Workflow de n8n importado y activado exitosamente."
else
    echo "[AVISO] Comando n8n no encontrado en PATH global."
fi

# 4. Iniciar y reiniciar servicios
echo "[4/4] Reiniciando servicios tgcf, tgcf-web y n8n..."
systemctl start n8n.service || true
systemctl restart tgcf.service || true
systemctl restart tgcf-web.service 2>/dev/null || true

sleep 2

echo ""
echo "========================================================"
echo "  ¡ACTUALIZACION COMPLETADA CON EXITO!"
echo "========================================================"
systemctl is-active tgcf.service && echo "  - tgcf (Reenvio + Metadatos Origen): 🟢 ACTIVO"
systemctl is-active tgcf-web.service && echo "  - tgcf-web (Panel Visual Canales):   🟢 ACTIVO"
systemctl is-active n8n.service && echo "  - n8n (Orquestador + Filtros LONG/SHORT): 🟢 ACTIVO"
systemctl is-active pocketbase.service && echo "  - PocketBase (Base de Datos):  🟢 ACTIVO"
echo "========================================================"
