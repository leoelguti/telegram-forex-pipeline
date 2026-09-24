import streamlit as st

from tgcf.web_ui.utils import hide_st, switch_theme
from tgcf.config import read_config

CONFIG = read_config()

st.set_page_config(
    page_title="Pipeline Señales MT5 - Dashboard",
    page_icon="📡",
    layout="wide",
)
hide_st(st)
switch_theme(st, CONFIG)

# Custom CSS para estilo profesional
st.markdown("""
<style>
    .metric-card {
        background-color: rgba(255, 255, 255, 0.05);
        border: 1px solid rgba(255, 255, 255, 0.12);
        border-radius: 10px;
        padding: 16px;
        margin-bottom: 12px;
        text-align: center;
    }
    .metric-val {
        font-size: 28px;
        font-weight: bold;
        color: #00d26a;
    }
    .metric-title {
        font-size: 14px;
        color: #a0aec0;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    .pipeline-badge {
        display: inline-block;
        padding: 4px 10px;
        border-radius: 6px;
        font-size: 13px;
        font-weight: 600;
        background-color: #1e3a5f;
        color: #60a5fa;
        margin-right: 6px;
    }
</style>
""", unsafe_allow_html=True)

st.title("📡 Telegram ➔ MT5 Forex Signal Pipeline")
st.caption("Sistema automatizado de captura de señales, inyección de metadatos de origen y orquestación con IA.")

st.divider()

# Métricas Principales
col1, col2, col3, col4 = st.columns(4)

total_forwards = len(CONFIG.forwards)
active_forwards = sum(1 for f in CONFIG.forwards if f.use_this)
mode_text = "🟢 En Vivo (Live)" if CONFIG.mode == 0 else "🟡 Histórico (Past)"
is_running = False
if CONFIG.pid != 0:
    import os
    try:
        os.kill(CONFIG.pid, 0)
        is_running = True
    except (ProcessLookupError, PermissionError, OSError):
        is_running = False
if not is_running:
    try:
        import subprocess
        res = subprocess.run(["systemctl", "is-active", "--quiet", "tgcf.service"])
        if res.returncode == 0:
            is_running = True
    except Exception:
        pass

with col1:
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-title">Canales Fuentes</div>
        <div class="metric-val">{active_forwards} / {total_forwards}</div>
        <small style="color: #68d391;">Canales activos</small>
    </div>
    """, unsafe_allow_html=True)

with col2:
    status_label = "🟢 ACTIVO" if is_running else "🔴 DETENIDO"
    status_color = "#00d26a" if is_running else "#f87171"
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-title">Servicio Reenvío</div>
        <div class="metric-val" style="color: {status_color};">{status_label}</div>
        <small style="color: #a0aec0;">PID: {CONFIG.pid if is_running else 'Inactivo'}</small>
    </div>
    """, unsafe_allow_html=True)

with col3:
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-title">Modo de Operación</div>
        <div class="metric-val" style="font-size: 22px; color: #60a5fa;">{mode_text}</div>
        <small style="color: #a0aec0;">Monitoreo en tiempo real</small>
    </div>
    """, unsafe_allow_html=True)

with col4:
    st.markdown("""
    <div class="metric-card">
        <div class="metric-title">Atribución de Canal</div>
        <div class="metric-val" style="font-size: 20px; color: #fbbf24;">⚡ ACTIVA</div>
        <small style="color: #a0aec0;">Tag [ORIGIN_ID|NAME] para MT5</small>
    </div>
    """, unsafe_allow_html=True)

st.write("")

# Canales configurados
st.subheader("📋 Canales Conectados al Pipeline")

if total_forwards == 0:
    st.info("No hay canales configurados. Dirígete a la pestaña **Conexiones** en la barra lateral para agregar el primer canal.")
else:
    for idx, fwd in enumerate(CONFIG.forwards):
        status_icon = "🟢" if fwd.use_this else "⚪"
        con_name = fwd.con_name or f"Conexión #{idx + 1}"
        dest_str = ", ".join(str(d) for d in fwd.dest) if fwd.dest else "Sin destino"
        
        with st.container():
            c1, c2, c3 = st.columns([3, 4, 3])
            with c1:
                st.write(f"**{status_icon} {con_name}**")
            with c2:
                st.code(f"Origen: {fwd.source}", language="text")
            with c3:
                st.caption(f"Destino MT5: `{dest_str}`")

st.divider()

# Arquitectura y Flujo de Señales
st.subheader("🔄 Arquitectura del Flujo de Datos")
st.markdown("""
1. **Captura (VPS / tgcf):** Telethon escucha las señales en tiempo real en los canales VIP/fuentes.
2. **Inyección de Atribución:** Se adjunta el identificador y nombre del canal origen `[ORIGIN_ID:<id>|NAME:<nombre>]`.
3. **Reenvío Seguro:** Se copia el mensaje al canal privado destino de MT5 sin enlaces de reenvío expuestos.
4. **Orquestación (n8n Webhook):** Se evalúan filtros rápidos (BUY/SELL/LONG/SHORT), IA Groq (Llama 3.3) extrae parámetros, y Fallback Regex inteligente asegura redundancia.
5. **Auditoría (PocketBase):** Registro automático de mensajes y métricas en `logs_mensajes` y `trades_metricas` con `canal_id` asociado.
6. **Ejecución (MetaTrader 5):** EA/Servicio abre la orden en MT5 colocando el nombre del canal en el comentario de la orden (máx. 31 chars).
""")

# Enlaces directos a las plataformas del VPS
st.subheader("🔗 Accesos Rápidos del Sistema")
ac1, ac2 = st.columns(2)
with ac1:
    st.markdown("""
    **⚙️ n8n Orquestador**  
    Flujos de trabajo, parsing con IA y webhooks:  
    👉 [Abrir n8n Web UI (Puerto 5678)](http://209.145.54.168:5678)
    """)
with ac2:
    st.markdown("""
    **🗄️ PocketBase Base de Datos**  
    Historial de mensajes, métricas y auditoría de trades:  
    👉 [Abrir PocketBase Admin (Puerto 8090)](http://209.145.54.168:8090/_/)
    """)
