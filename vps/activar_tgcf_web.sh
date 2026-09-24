#!/usr/bin/env bash
# ==============================================================================
# Script para activar el panel visual web de tgcf (Streamlit) en Ubuntu VPS
# Puerto: 8501
# ==============================================================================

set -e

PROJECT_DIR="/opt/trading-forex-pipeline"
cd "$PROJECT_DIR"

echo "========================================================"
echo "    ACTIVANDO PANEL WEB VISUAL DE TGCF EN VPS"
echo "========================================================"

# 1. Habilitar puerto 8501 en el firewall UFW
echo "[1/4] Abriendo puerto 8501 en firewall UFW..."
if command -v ufw &> /dev/null; then
    ufw allow 8501/tcp comment "tgcf Web UI" || true
fi

# 2. Configurar servicio systemd para tgcf-web
echo "[2/4] Creando servicio systemd tgcf-web.service..."
cat << 'EOF' > /etc/systemd/system/tgcf-web.service
[Unit]
Description=tgcf Web UI - Telegram Forex Forwarder Dashboard
After=network.target tgcf.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/trading-forex-pipeline/my-tgcf
Environment="STREAMLIT_SERVER_PORT=8501"
Environment="STREAMLIT_SERVER_ADDRESS=0.0.0.0"
Environment="STREAMLIT_SERVER_HEADLESS=true"
ExecStart=/opt/trading-forex-pipeline/my-tgcf/.venv/bin/streamlit run /opt/trading-forex-pipeline/my-tgcf/tgcf/web_ui/0_👋_Hello.py --server.port 8501 --server.address 0.0.0.0 --server.headless true
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 3. Recargar systemd y arrancar tgcf-web
echo "[3/4] Iniciando servicio tgcf-web..."
systemctl daemon-reload
systemctl enable --now tgcf-web.service
systemctl restart tgcf-web.service

sleep 2

# 4. Obtener IP y confirmar estado
echo "[4/4] Verificando estado del servicio..."
PUBLIC_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

echo ""
echo "========================================================"
echo "  ¡PANEL WEB DE TGCF ACTIVADO EXITOSAMENTE!"
echo "========================================================"
systemctl is-active tgcf-web.service && echo "  - Estado tgcf-web: 🟢 ACTIVO"
echo ""
echo "Accede a la interfaz visual en tu navegador:"
echo "👉 http://${PUBLIC_IP}:8501"
echo ""
echo "Contraseña de acceso por defecto (si la solicita): tgcf"
echo "========================================================"
