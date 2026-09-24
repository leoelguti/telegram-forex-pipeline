import datetime
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

import pandas as pd
import streamlit as st

from tgcf.config import CONFIG, read_config, write_config
from tgcf.web_ui.password import check_password
from tgcf.web_ui.utils import hide_st, switch_theme

CONFIG = read_config()

st.set_page_config(
    page_title="Inteligencia de Canales y Rendimiento - tgcf",
    page_icon="📊",
    layout="wide",
)
hide_st(st)
switch_theme(st, CONFIG)

# Custom CSS para dashboard financiero moderno
st.markdown(
    """
<style>
    .metric-card {
        background-color: rgba(255, 255, 255, 0.04);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 10px;
        padding: 16px;
        text-align: center;
        margin-bottom: 12px;
    }
    .metric-val-positive {
        font-size: 26px;
        font-weight: 800;
        color: #00d26a;
    }
    .metric-val-negative {
        font-size: 26px;
        font-weight: 800;
        color: #f83245;
    }
    .metric-val-neutral {
        font-size: 26px;
        font-weight: 800;
        color: #e2e8f0;
    }
    .metric-lbl {
        font-size: 13px;
        color: #a0aec0;
        text-transform: uppercase;
        font-weight: 600;
        margin-top: 4px;
    }
    .channel-box {
        background: rgba(255, 255, 255, 0.02);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 8px;
        padding: 14px;
        margin-bottom: 10px;
    }
    .badge-win {
        background: rgba(0, 210, 106, 0.15);
        color: #00d26a;
        padding: 3px 8px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: bold;
    }
    .badge-loss {
        background: rgba(248, 50, 69, 0.15);
        color: #f83245;
        padding: 3px 8px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: bold;
    }
</style>
""",
    unsafe_allow_html=True,
)


def get_pb_url():
    """Obtiene el endpoint de PocketBase de acuerdo al entorno."""
    if os.environ.get("POCKETBASE_URL"):
        return os.environ.get("POCKETBASE_URL")
    if os.name != "nt":
        return "http://127.0.0.1:8090"
    return "http://209.145.54.168:8090"


def pb_request(endpoint, method="GET", data=None):
    """Realiza peticiones HTTP a la API REST de PocketBase."""
    base = get_pb_url()
    url = f"{base}/api/{endpoint}"
    headers = {"Content-Type": "application/json"}
    body = json.dumps(data).encode("utf-8") if data else None

    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            res_text = r.read().decode("utf-8")
            if res_text:
                return json.loads(res_text)
            return {}
    except urllib.error.HTTPError as err:
        return {"error": err.code, "message": str(err)}
    except Exception as e:
        return {"error": 500, "message": str(e)}


def fetch_all_trades():
    """Descarga el historial de trades auditados desde PocketBase."""
    res = pb_request("collections/trades_metricas/records?perPage=500")
    if isinstance(res, dict) and "items" in res:
        return res["items"]
    return []


def fetch_all_channels():
    """Descarga los canales fuente configurados en PocketBase."""
    res = pb_request("collections/canales_fuente/records?perPage=100")
    if isinstance(res, dict) and "items" in res:
        return res["items"]
    return []


def fetch_recent_logs():
    """Descarga los registros de mensajes recientes para calcular tasa de ruido."""
    res = pb_request("collections/logs_mensajes/records?perPage=500")
    if isinstance(res, dict) and "items" in res:
        return res["items"]
    return []


def restart_tgcf_service():
    """Aplica reinicio inmediato a tgcf.service en VPS."""
    if os.name != "nt":
        try:
            subprocess.run(["systemctl", "restart", "tgcf.service"], capture_output=True)
            return True
        except Exception:
            pass
    return False


def toggle_channel_state(chan_identifier, chan_name, new_state_bool):
    """
    Pausa o activa un canal simultáneamente en tgcf y en PocketBase.
    """
    config_obj = read_config()
    target_str = str(chan_identifier).strip()

    # 1. Actualizar configuración en tgcf
    found_in_tgcf = False
    for f in config_obj.forwards:
        f_src = str(f.source).strip()
        f_name = str(f.con_name).strip()
        if (
            f_src == target_str
            or target_str in f_src
            or f_src in target_str
            or f_name == chan_name
        ):
            f.use_this = new_state_bool
            found_in_tgcf = True
            break

    if found_in_tgcf:
        write_config(config_obj)
        restart_tgcf_service()

    # 2. Actualizar estado en PocketBase
    canales = fetch_all_channels()
    for c in canales:
        c_id = str(c.get("channel_id", "")).strip()
        c_name = str(c.get("nombre", "")).strip()
        if (
            c_id == target_str
            or target_str in c_id
            or c_id in target_str
            or c_name == chan_name
        ):
            pb_record_id = c.get("id")
            pb_request(
                f"collections/canales_fuente/records/{pb_record_id}",
                method="PATCH",
                data={"estado": "activo" if new_state_bool else "inactivo"},
            )
            break

    return True


if check_password(st):
    st.title("📊 Rendimiento y Auditoría de Proveedores de Señales")
    st.caption(
        "Telemetría en tiempo real desde MetaTrader 5 y PocketBase. Evalúa la rentabilidad y calidad de cada canal origen."
    )

    # Controles superiores
    top_c1, top_c2, top_c3 = st.columns([4, 4, 2])
    with top_c1:
        time_filter = st.selectbox(
            "📅 Ventana Temporal",
            ["Todo el Historial", "Hoy", "Últimos 7 días", "Últimos 30 días"],
            index=0,
        )
    with top_c2:
        pb_status_str = "🟢 Conectado"
        try:
            h = pb_request("health")
            if h.get("code") != 200:
                pb_status_str = "🔴 Desconectado"
        except Exception:
            pb_status_str = "🔴 Error Conexión"
        st.write("")
        st.caption(f"Base de Datos PocketBase: **{pb_status_str}** (`{get_pb_url()}`)")

    with top_c3:
        st.write("")
        if st.button("🔄 Refrescar Datos", use_container_width=True):
            st.rerun()

    # Cargar datos desde PocketBase
    trades = fetch_all_trades()
    channels = fetch_all_channels()
    logs = fetch_recent_logs()

    # Mapeo de IDs a nombres amigables de canales
    chan_map = {}
    for c in channels:
        cid = str(c.get("channel_id", "")).strip()
        cname = str(c.get("nombre", "")).strip()
        if cid:
            chan_map[cid] = cname
            if cid.startswith("-100"):
                chan_map[cid[4:]] = cname

    for f in CONFIG.forwards:
        f_src = str(f.source).strip()
        f_name = str(f.con_name).strip()
        if f_src:
            chan_map[f_src] = f_name
            if f_src.startswith("-100"):
                chan_map[f_src[4:]] = f_name

    # Procesar Trades
    processed_trades = []
    for t in trades:
        cid = str(t.get("canal_id", "")).strip()
        cname = chan_map.get(cid, cid)
        if not cname:
            cname = "Canal Desconocido"

        created_str = t.get("created", "")
        dt_val = None
        if created_str:
            try:
                dt_val = datetime.datetime.fromisoformat(
                    created_str.replace("Z", "+00:00")
                )
            except Exception:
                pass

        processed_trades.append(
            {
                "id": t.get("id"),
                "ticket": t.get("ticket_mt5"),
                "canal_id": cid,
                "canal_nombre": cname,
                "par": t.get("par"),
                "accion": t.get("accion"),
                "lotaje": float(t.get("lotaje", 0.0) or 0.0),
                "precio_entrada": float(t.get("precio_entrada", 0.0) or 0.0),
                "precio_cierre": float(t.get("precio_cierre", 0.0) or 0.0),
                "stop_loss": float(t.get("stop_loss", 0.0) or 0.0),
                "take_profit": float(t.get("take_profit", 0.0) or 0.0),
                "profit_usd": float(t.get("profit_usd", 0.0) or 0.0),
                "pips": float(t.get("pips", 0.0) or 0.0),
                "estado": t.get("estado_trade", "ABIERTO"),
                "fecha": dt_val,
                "fecha_str": created_str[:16].replace("T", " ") if created_str else "-",
            }
        )

    # Filtrar por ventana temporal si aplica
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    filtered_trades = []
    for pt in processed_trades:
        if not pt["fecha"]:
            filtered_trades.append(pt)
            continue

        if time_filter == "Hoy":
            if pt["fecha"].date() == now_utc.date():
                filtered_trades.append(pt)
        elif time_filter == "Últimos 7 días":
            if (now_utc - pt["fecha"]).total_seconds() <= 7 * 86400:
                filtered_trades.append(pt)
        elif time_filter == "Últimos 30 días":
            if (now_utc - pt["fecha"]).total_seconds() <= 30 * 86400:
                filtered_trades.append(pt)
        else:
            filtered_trades.append(pt)

    # Métricas Globales
    closed_trades = [t for t in filtered_trades if t["estado"] == "CERRADO"]
    open_trades = [t for t in filtered_trades if t["estado"] == "ABIERTO"]

    total_closed = len(closed_trades)
    wins = [t for t in closed_trades if t["profit_usd"] > 0]
    losses = [t for t in closed_trades if t["profit_usd"] < 0]
    be_count = [t for t in closed_trades if t["profit_usd"] == 0]

    net_profit_usd = sum(t["profit_usd"] for t in closed_trades)
    net_pips = sum(t["pips"] for t in closed_trades)
    win_rate = (len(wins) / total_closed * 100.0) if total_closed > 0 else 0.0

    gross_profit = sum(t["profit_usd"] for t in wins)
    gross_loss = abs(sum(t["profit_usd"] for t in losses))
    profit_factor = (
        (gross_profit / gross_loss)
        if gross_loss > 0
        else (gross_profit if gross_profit > 0 else 1.0)
    )

    # Fila de Tarjetas de Métricas Institucionales
    kpi_col1, kpi_col2, kpi_col3, kpi_col4, kpi_col5 = st.columns(5)

    with kpi_col1:
        color_cls = (
            "metric-val-positive"
            if net_profit_usd > 0
            else ("metric-val-negative" if net_profit_usd < 0 else "metric-val-neutral")
        )
        st.markdown(
            f"""
        <div class="metric-card">
            <div class="{color_cls}">${net_profit_usd:+.2f} USD</div>
            <div class="metric-lbl">Beneficio Neto Total</div>
        </div>
        """,
            unsafe_allow_html=True,
        )

    with kpi_col2:
        pips_color = (
            "metric-val-positive"
            if net_pips > 0
            else ("metric-val-negative" if net_pips < 0 else "metric-val-neutral")
        )
        st.markdown(
            f"""
        <div class="metric-card">
            <div class="{pips_color}">{net_pips:+.1f} Pips</div>
            <div class="metric-lbl">Pips Acumulados</div>
        </div>
        """,
            unsafe_allow_html=True,
        )

    with kpi_col3:
        wr_color = (
            "metric-val-positive"
            if win_rate >= 50
            else ("metric-val-negative" if total_closed > 0 else "metric-val-neutral")
        )
        st.markdown(
            f"""
        <div class="metric-card">
            <div class="{wr_color}">{win_rate:.1f}%</div>
            <div class="metric-lbl">Tasa de Acierto (Win Rate)</div>
        </div>
        """,
            unsafe_allow_html=True,
        )

    with kpi_col4:
        pf_color = (
            "metric-val-positive"
            if profit_factor >= 1.5
            else (
                "metric-val-negative"
                if profit_factor < 1.0
                else "metric-val-neutral"
            )
        )
        st.markdown(
            f"""
        <div class="metric-card">
            <div class="{pf_color}">{profit_factor:.2f}</div>
            <div class="metric-lbl">Factor de Ganancia (PF)</div>
        </div>
        """,
            unsafe_allow_html=True,
        )

    with kpi_col5:
        st.markdown(
            f"""
        <div class="metric-card">
            <div class="metric-val-neutral">{total_closed} <span style="font-size:16px; color:#a0aec0;">({len(open_trades)} abiertos)</span></div>
            <div class="metric-lbl">Operaciones Totales</div>
        </div>
        """,
            unsafe_allow_html=True,
        )

    st.markdown("---")

    # SECCION 1: RANKING DE CANALES Y CONTROL DE PAUSA
    st.subheader("🏆 Ranking de Rentabilidad por Canal de Telegram")
    st.caption(
        "Analiza qué canal aporta ganancias consistentes y apaga con un solo clic aquellos con resultados desfavorables."
    )

    # Agrupar métricas por canal
    channel_stats = {}

    # Inicializar con canales conocidos
    for f in CONFIG.forwards:
        c_src = str(f.source).strip()
        c_name = f.con_name.strip() if f.con_name else f"Canal_{c_src}"
        channel_stats[c_src] = {
            "nombre": c_name,
            "canal_id": c_src,
            "activo_tgcf": f.use_this,
            "total": 0,
            "wins": 0,
            "losses": 0,
            "be": 0,
            "profit_usd": 0.0,
            "pips": 0.0,
        }

    for c in channels:
        cid = str(c.get("channel_id", "")).strip()
        cname = str(c.get("nombre", "")).strip()
        est = str(c.get("estado", "activo")).strip()
        if cid not in channel_stats:
            channel_stats[cid] = {
                "nombre": cname or cid,
                "canal_id": cid,
                "activo_tgcf": (est == "activo"),
                "total": 0,
                "wins": 0,
                "losses": 0,
                "be": 0,
                "profit_usd": 0.0,
                "pips": 0.0,
            }

    # Sumar resultados de cada trade al canal
    for t in closed_trades:
        cid = t["canal_id"]
        # Buscar key más cercana
        matched_key = None
        for k in channel_stats:
            if k == cid or k in cid or cid in k:
                matched_key = k
                break

        if not matched_key:
            matched_key = cid
            channel_stats[matched_key] = {
                "nombre": t["canal_nombre"],
                "canal_id": cid,
                "activo_tgcf": True,
                "total": 0,
                "wins": 0,
                "losses": 0,
                "be": 0,
                "profit_usd": 0.0,
                "pips": 0.0,
            }

        st_obj = channel_stats[matched_key]
        st_obj["total"] += 1
        st_obj["profit_usd"] += t["profit_usd"]
        st_obj["pips"] += t["pips"]
        if t["profit_usd"] > 0:
            st_obj["wins"] += 1
        elif t["profit_usd"] < 0:
            st_obj["losses"] += 1
        else:
            st_obj["be"] += 1

    # Ordenar canales por mayor beneficio en USD
    sorted_channels = sorted(
        channel_stats.values(), key=lambda x: x["profit_usd"], reverse=True
    )

    if sorted_channels:
        for idx, cs in enumerate(sorted_channels):
            c_name = cs["nombre"]
            c_id = cs["canal_id"]
            tot = cs["total"]
            p_usd = cs["profit_usd"]
            c_pips = cs["pips"]
            w = cs["wins"]
            l = cs["losses"]
            is_active = cs["activo_tgcf"]
            c_wr = (w / tot * 100.0) if tot > 0 else 0.0

            badge_color = "#00d26a" if p_usd >= 0 else "#f83245"
            status_badge = (
                "🟢 ACTIVO"
                if is_active
                else "⏸️ PAUSADO"
            )

            with st.container():
                col_info, col_wr, col_pnl, col_btn = st.columns([4, 2, 2, 2])
                with col_info:
                    st.markdown(
                        f"**{idx + 1}. {c_name}** `({c_id})`  \n"
                        f"<span style='font-size:12px; color:#a0aec0;'>Estado: **{status_badge}** | Trades cerrados: **{tot}** ({w}W / {l}L)</span>",
                        unsafe_allow_html=True,
                    )
                with col_wr:
                    st.metric("Win Rate", f"{c_wr:.1f}%")
                with col_pnl:
                    st.metric("PnL Acumulado", f"${p_usd:+.2f} USD", f"{c_pips:+.1f} pips")
                with col_btn:
                    st.write("")
                    if is_active:
                        if st.button("⏸️ Pausar", key=f"pause_{c_id}_{idx}", type="secondary", use_container_width=True):
                            toggle_channel_state(c_id, c_name, False)
                            st.warning(f"Canal '{c_name}' pausado. No se reenviarán señales a MT5.")
                            time.sleep(1)
                            st.rerun()
                    else:
                        if st.button("▶️ Activar", key=f"activate_{c_id}_{idx}", type="primary", use_container_width=True):
                            toggle_channel_state(c_id, c_name, True)
                            st.success(f"Canal '{c_name}' activado.")
                            time.sleep(1)
                            st.rerun()

                st.markdown("<hr style='margin:4px 0 12px 0; border:0; border-top:1px solid rgba(255,255,255,0.06);'>", unsafe_allow_html=True)
    else:
        st.info("No hay canales configurados aún.")

    st.markdown("---")

    # SECCION 2: GRAFICOS INTERACTIVOS (CURVA DE CAPITAL Y SIMBOLOS)
    st.subheader("📈 Visualización Gráfica del Portafolio")
    graph_c1, graph_c2 = st.columns(2)

    with graph_c1:
        st.markdown("**Curva de Capital Acumulada ($ USD)**")
        if closed_trades:
            # Crear serie temporal o secuencial de balance acumulado
            accum = []
            curr_b = 0.0
            for idx, t in enumerate(closed_trades):
                curr_b += t["profit_usd"]
                accum.append({"Operación": idx + 1, "Ganancia Acumulada ($)": curr_b})
            df_curve = pd.DataFrame(accum)
            st.line_chart(df_curve, x="Operación", y="Ganancia Acumulada ($)", color="#00d26a")
        else:
            st.info("Se graficará automáticamente conforme se cierren operaciones en MT5.")

    with graph_c2:
        st.markdown("**Rendimiento Neto por Instrumento ($ USD)**")
        if closed_trades:
            sym_stats = {}
            for t in closed_trades:
                sym = t["par"]
                sym_stats[sym] = sym_stats.get(sym, 0.0) + t["profit_usd"]
            df_sym = pd.DataFrame(list(sym_stats.items()), columns=["Par", "PnL ($)"]).sort_values(by="PnL ($)", ascending=False)
            st.bar_chart(df_sym, x="Par", y="PnL ($)", color="#4A90E2")
        else:
            st.info("Sin operaciones cerradas para desglosar por instrumento.")

    st.markdown("---")

    # SECCION 3: AUDITORIA DE CALIDAD DE SEÑALES Y RUIDO
    with st.expander("🛡️ Auditoría de Calidad y Detección de Ruido por Canal", expanded=False):
        st.caption("Compara la cantidad de mensajes totales de Telegram contra las órdenes ejecutadas en MT5 y los mensajes descartados (spam o sin formato).")
        if logs:
            chan_log_stats = {}
            for entry in logs:
                c_id = str(entry.get("canal_id", "")).strip()
                c_name = chan_map.get(c_id, c_id)
                estado = entry.get("estado", "DESCARTADO")

                if c_name not in chan_log_stats:
                    chan_log_stats[c_name] = {"Total": 0, "Ejecutadas": 0, "Descartadas": 0, "Riesgo": 0}

                chan_log_stats[c_name]["Total"] += 1
                if estado == "ENVIADO_MT5":
                    chan_log_stats[c_name]["Ejecutadas"] += 1
                elif estado == "RECHAZO_RIESGO":
                    chan_log_stats[c_name]["Riesgo"] += 1
                else:
                    chan_log_stats[c_name]["Descartadas"] += 1

            log_rows = []
            for cname, st_val in chan_log_stats.items():
                tot_m = st_val["Total"]
                ej = st_val["Ejecutadas"]
                ef = (ej / tot_m * 100.0) if tot_m > 0 else 0.0
                log_rows.append({
                    "Canal": cname,
                    "Mensajes Totales": tot_m,
                    "Señales Válidas (MT5)": ej,
                    "Descartadas / Spam": st_val["Descartadas"],
                    "Rechazos de Riesgo": st_val["Riesgo"],
                    "Eficiencia de Señal": f"{ef:.1f}%",
                })
            df_logs = pd.DataFrame(log_rows)
            st.dataframe(df_logs, use_container_width=True)
        else:
            st.info("Sin registros de mensajes en PocketBase aún.")

    st.markdown("---")

    # SECCION 4: LIBRO DE REGISTRO DETALLADO (TRADE JOURNAL)
    st.subheader("📋 Libro Diario de Operaciones Ejecutadas (Trade Journal)")
    st.caption("Historial auditable orden por orden con parámetros de entrada, salida, stop loss, take profit y PnL.")

    if filtered_trades:
        # Filtros de tabla
        filt_c1, filt_c2 = st.columns(2)
        with filt_c1:
            sym_list = ["Todos"] + sorted(list(set(t["par"] for t in filtered_trades if t["par"])))
            sel_sym = st.selectbox("Filtrar por Par / Instrumento", sym_list)
        with filt_c2:
            st_list = ["Todos", "CERRADO", "ABIERTO"]
            sel_status = st.selectbox("Filtrar por Estado", st_list)

        display_trades = filtered_trades
        if sel_sym != "Todos":
            display_trades = [t for t in display_trades if t["par"] == sel_sym]
        if sel_status != "Todos":
            display_trades = [t for t in display_trades if t["estado"] == sel_status]

        table_rows = []
        for t in display_trades:
            p_val = t["profit_usd"]
            res_icon = "🟢 GANADA" if p_val > 0 else ("🔴 PERDIDA" if p_val < 0 else "⚪ BE / ABIERTO")
            table_rows.append({
                "Ticket": t["ticket"],
                "Fecha": t["fecha_str"],
                "Canal": t["canal_nombre"],
                "Par": t["par"],
                "Acción": t["accion"],
                "Lote": f"{t['lotaje']:.2f}",
                "Entrada": f"{t['precio_entrada']:.5f}",
                "Cierre": f"{t['precio_cierre']:.5f}" if t["precio_cierre"] > 0 else "-",
                "Stop Loss": f"{t['stop_loss']:.5f}",
                "Take Profit": f"{t['take_profit']:.5f}",
                "PnL ($)": f"${p_val:+.2f}",
                "Pips": f"{t['pips']:+.1f}",
                "Resultado": res_icon,
            })

        df_trades = pd.DataFrame(table_rows)
        st.dataframe(df_trades, use_container_width=True)

        # Botón de exportación a CSV
        csv_data = df_trades.to_csv(index=False).encode("utf-8")
        st.download_button(
            "📥 Descargar Informe Completo (CSV)",
            data=csv_data,
            file_name=f"informe_trades_forex_{time_filter.lower().replace(' ', '_')}.csv",
            mime="text/csv",
        )
    else:
        st.info("No se han registrado operaciones en el período seleccionado.")
