#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE DESPLIEGUE AUTOMATIZADO EN VPS UBUNTU
# Pipeline: Telegram -> tgcf -> n8n -> Groq -> MT5 -> PocketBase
# ==============================================================================

set -e

echo "========================================================"
echo "    INSTALADOR Y DESPLIEGUE EN VPS UBUNTU (FOREX PIPELINE)"
echo "========================================================"

# Verificar privilegios sudo/root
if [ "$EUID" -ne 0 ]; then
    echo "[AVISO] Ejecutando con sudo..."
    exec sudo bash "$0" "$@"
fi

CURRENT_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$CURRENT_USER")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Directorio del proyecto: $PROJECT_DIR"
echo "Usuario de ejecucion:    $CURRENT_USER"
echo ""

# 1. Actualizar repositorios e instalar paquetes base
echo "[1/6] Instalando dependencias del sistema operativo..."
apt-get update -q
apt-get install -y -q curl wget unzip git build-essential \
    python3 python3-venv python3-pip python3-dev ufw

# 2. Instalar Node.js LTS (v20) y n8n
echo "[2/6] Verificando Node.js y n8n..."
if ! command -v node &> /dev/null; then
    echo "Instalando Node.js v20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -q nodejs
fi

if ! command -v n8n &> /dev/null; then
    echo "Instalando n8n globalmente con npm..."
    npm install -g n8n --quiet
fi

# 3. Descargar PocketBase para Linux
echo "[3/6] Configurando PocketBase para Linux..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    PB_ARCH="linux_amd64"
elif [ "$ARCH" = "aarch64" ]; then
    PB_ARCH="linux_arm64"
else
    PB_ARCH="linux_amd64"
fi

mkdir -p "$PROJECT_DIR/pocketbase"
if [ ! -f "$PROJECT_DIR/pocketbase/pocketbase" ]; then
    echo "Descargando PocketBase ($PB_ARCH)..."
    wget -q "https://github.com/pocketbase/pocketbase/releases/download/v0.25.9/pocketbase_0.25.9_${PB_ARCH}.zip" -O /tmp/pb.zip
    unzip -q -o /tmp/pb.zip pocketbase -d "$PROJECT_DIR/pocketbase/"
    chmod +x "$PROJECT_DIR/pocketbase/pocketbase"
    rm -f /tmp/pb.zip
    echo "PocketBase instalado con exito."
else
    chmod +x "$PROJECT_DIR/pocketbase/pocketbase"
    echo "PocketBase ya existe."
fi

# 4. Configurar entorno virtual de Python para tgcf
echo "[4/6] Configurando entorno virtual para tgcf..."
cd "$PROJECT_DIR/my-tgcf"
if [ ! -d ".venv" ]; then
    sudo -u "$CURRENT_USER" python3 -m venv .venv
fi

sudo -u "$CURRENT_USER" bash -c "
    source .venv/bin/activate
    pip install --upgrade pip --quiet
    if [ -f requirements.txt ]; then
        pip install -r requirements.txt --quiet
    fi
    pip install -e . --quiet
"

# 5. Configurar variables de n8n
echo "[5/6] Verificando configuraciones de n8n..."
PUBLIC_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
N8N_ENV="$PROJECT_DIR/n8n/.env"

if [ ! -f "$N8N_ENV" ]; then
    if [ -f "$PROJECT_DIR/n8n/.env.example" ]; then
        cp "$PROJECT_DIR/n8n/.env.example" "$N8N_ENV"
    fi
fi

# Asegurar que n8n escuche externamente
if [ -f "$N8N_ENV" ]; then
    sed -i 's/^N8N_LISTEN_ADDRESS=.*/N8N_LISTEN_ADDRESS=0.0.0.0/' "$N8N_ENV" 2>/dev/null || true
    sed -i 's/^N8N_HOST=.*/N8N_HOST=0.0.0.0/' "$N8N_ENV" 2>/dev/null || true
    sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=http://${PUBLIC_IP}:5678/|" "$N8N_ENV" 2>/dev/null || true
    sed -i "s|^N8N_USER_FOLDER=.*|N8N_USER_FOLDER=${PROJECT_DIR}/n8n/.n8n|" "$N8N_ENV" 2>/dev/null || true
    if ! grep -q "N8N_SECURE_COOKIE" "$N8N_ENV"; then
        echo "N8N_SECURE_COOKIE=false" >> "$N8N_ENV"
    else
        sed -i 's/^N8N_SECURE_COOKIE=.*/N8N_SECURE_COOKIE=false/' "$N8N_ENV" 2>/dev/null || true
    fi
fi

# Importar y activar workflow en n8n
if [ -f "$PROJECT_DIR/n8n/workflow_forex_signal_pipeline.json" ]; then
    echo "Importando workflow en n8n..."
    n8n import:workflow --input="$PROJECT_DIR/n8n/workflow_forex_signal_pipeline.json" 2>/dev/null || true
    n8n update:workflow --all --active=true 2>/dev/null || true
fi

# Asegurar permisos del proyecto
chown -R "$CURRENT_USER:$CURRENT_USER" "$PROJECT_DIR"

# 6. Crear y activar servicios systemd
echo "[6/6] Creando servicios systemd para ejecucion 24/7..."

# 6.1 Servicio PocketBase
cat <<EOF > /etc/systemd/system/pocketbase.service
[Unit]
Description=PocketBase - Forex Signal Pipeline
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR/pocketbase
ExecStart=$PROJECT_DIR/pocketbase/pocketbase serve --http=0.0.0.0:8090
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 6.2 Servicio n8n
N8N_BIN=$(which n8n)
cat <<EOF > /etc/systemd/system/n8n.service
[Unit]
Description=n8n Orchestrator - Forex Signal Pipeline
After=network.target pocketbase.service

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR/n8n
EnvironmentFile=-$PROJECT_DIR/n8n/.env
ExecStart=$N8N_BIN start
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 6.3 Servicio tgcf Live
cat <<EOF > /etc/systemd/system/tgcf.service
[Unit]
Description=tgcf Live - Telegram Forex Channel Forwarder
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR/my-tgcf
ExecStart=$PROJECT_DIR/my-tgcf/.venv/bin/tgcf --loud live
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y arrancar servicios
systemctl daemon-reload
systemctl enable --now pocketbase.service
systemctl enable --now n8n.service
systemctl enable --now tgcf.service

# Configurar puertos en firewall si UFW esta activo
if ufw status | grep -q "active"; then
    echo "Abriendo puertos en firewall UFW (5678, 8090)..."
    ufw allow 5678/tcp comment "n8n Webhook"
    ufw allow 8090/tcp comment "PocketBase"
fi

echo ""
echo "========================================================"
echo "          DESPLIEGUE EN VPS COMPLETADO CON EXITO!"
echo "========================================================"
echo "IP Publica de este VPS:  $PUBLIC_IP"
echo ""
echo "Estado de los servicios:"
systemctl is-active pocketbase.service && echo "  - PocketBase: 🟢 ACTIVO (http://$PUBLIC_IP:8090/_/)"
systemctl is-active n8n.service && echo "  - n8n:        🟢 ACTIVO (http://$PUBLIC_IP:5678)"
systemctl is-active tgcf.service && echo "  - tgcf Live:  🟢 ACTIVO (Monitoreando canales Telegram)"
echo ""
echo "Para ver logs en vivo del reenvio:"
echo "  sudo journalctl -u tgcf -f"
echo "  sudo journalctl -u n8n -f"
echo ""
echo "Configuracion necesaria en MetaTrader 5 (Windows):"
echo "  - InpN8nWebhookUrl: http://$PUBLIC_IP:5678/webhook/signal"
echo "  - InpPocketBaseUrl: http://$PUBLIC_IP:8090"
echo "========================================================"
