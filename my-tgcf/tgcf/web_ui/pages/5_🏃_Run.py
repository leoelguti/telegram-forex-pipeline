import os
import signal
import subprocess
import time

import streamlit as st

from tgcf.config import CONFIG, read_config, write_config
from tgcf.web_ui.password import check_password
from tgcf.web_ui.utils import hide_st, switch_theme

CONFIG = read_config()


def termination():
    st.success("✅ Proceso detenido correctamente.")
    if os.path.exists("logs.txt"):
        try:
            os.replace("logs.txt", "old_logs.txt")
        except Exception:
            pass

    if os.path.exists("old_logs.txt"):
        with open("old_logs.txt", "r", encoding="utf-8", errors="ignore") as f:
            st.download_button(
                "📥 Descargar registros anteriores", data=f.read(), file_name="tgcf_logs.txt"
            )

    CONFIG = read_config()
    CONFIG.pid = 0
    write_config(CONFIG)
    st.button("🔄 Actualizar página")


st.set_page_config(
    page_title="Control de Ejecución - tgcf",
    page_icon="🏃",
    layout="wide",
)
hide_st(st)
switch_theme(st, CONFIG)

if check_password(st):
    st.title("🏃 Control de Ejecución y Monitoreo")
    st.caption("Gestiona el servicio de captura y reenvío de señales en tiempo real.")

    # Verificar estado del proceso
    is_systemd = False
    is_running = False
    if os.name != "nt":
        try:
            res = subprocess.run(["systemctl", "is-active", "--quiet", "tgcf.service"])
            if res.returncode == 0:
                is_running = True
                is_systemd = True
        except Exception:
            pass

    if not is_running and CONFIG.pid != 0:
        try:
            os.kill(CONFIG.pid, 0)
            is_running = True
        except (ProcessLookupError, PermissionError, OSError):
            is_running = False
            CONFIG.pid = 0
            write_config(CONFIG)

    # Banner de Estado
    col_status, col_actions = st.columns([6, 4])
    with col_status:
        if is_running:
            label = "🟢 **PIPELINE ACTIVO** — Servicio systemd en segundo plano (24/7)" if is_systemd else f"🟢 **PIPELINE ACTIVO** — Monitoreando canales en vivo (PID: `{CONFIG.pid}`)"
            st.success(label)
        else:
            st.error("🔴 **PIPELINE DETENIDO** — No se están reenviando señales actualmente.")

    with col_actions:
        if is_systemd:
            c_act1, c_act2 = st.columns(2)
            with c_act1:
                if st.button("🔄 Reiniciar", type="primary", use_container_width=True):
                    subprocess.run(["systemctl", "restart", "tgcf.service"])
                    st.success("Servicio reiniciado.")
                    time.sleep(1)
                    st.rerun()
            with c_act2:
                if st.button("⏹️ Detener", type="secondary", use_container_width=True):
                    subprocess.run(["systemctl", "stop", "tgcf.service"])
                    st.warning("Servicio detenido.")
                    time.sleep(1)
                    st.rerun()
        elif not is_running:
            if st.button("▶️ Iniciar Servicio tgcf", type="primary", use_container_width=True):
                if os.name != "nt":
                    try:
                        res = subprocess.run(["systemctl", "start", "tgcf.service"])
                        if res.returncode == 0:
                            st.success("Servicio systemd iniciado.")
                            time.sleep(1)
                            st.rerun()
                    except Exception:
                        pass
                mode_arg = "live" if CONFIG.mode == 0 else "past"
                with open("logs.txt", "a", encoding="utf-8") as logs:
                    process = subprocess.Popen(
                        ["tgcf", "--loud", mode_arg],
                        stdout=logs,
                        stderr=subprocess.STDOUT,
                        shell=(os.name == "nt"),
                    )
                CONFIG.pid = process.pid
                write_config(CONFIG)
                st.success(f"Servicio iniciado con PID: {process.pid}")
                time.sleep(1.5)
                st.rerun()
        else:
            if st.button("⏹️ Detener Servicio", type="primary", use_container_width=True):
                try:
                    sig = getattr(signal, "SIGTERM", 15)
                    os.kill(CONFIG.pid, sig)
                except Exception as err:
                    st.warning(f"Aviso al detener: {err}")
                CONFIG.pid = 0
                write_config(CONFIG)
                termination()
                time.sleep(1)
                st.rerun()

    st.markdown("---")

    # Configuración de Ejecución
    with st.expander("⚙️ Opciones de Ejecución del Reenvío", expanded=False):
        c1, c2 = st.columns(2)
        with c1:
            CONFIG.show_forwarded_from = st.checkbox(
                "Mostrar etiqueta 'Reenviado de' (Forwarded from)",
                value=CONFIG.show_forwarded_from,
                help="Desactivado (recomendado): tgcf envía una copia limpia inyectando los metadatos [ORIGIN_ID|NAME]."
            )
            mode_choice = st.radio("Modo de Ejecución", ["En Vivo (Live)", "Histórico (Past)"], index=CONFIG.mode)
            CONFIG.mode = 0 if mode_choice == "En Vivo (Live)" else 1

        with c2:
            if CONFIG.mode == 1:
                st.warning("El modo histórico requiere cuenta de usuario (no bot) y lee mensajes pasados.")
                CONFIG.past.delay = st.slider("Demora entre mensajes (segundos)", 0, 60, value=CONFIG.past.delay)
            else:
                CONFIG.live.delete_sync = st.checkbox(
                    "Sincronizar eliminación de mensajes",
                    value=CONFIG.live.delete_sync,
                    help="Si un mensaje se borra en el canal origen, borrarlo en el destino."
                )
                CONFIG.live.filter_spam = st.checkbox(
                    "🛡️ Filtro Anti-Spam y Publicidad",
                    value=getattr(CONFIG.live, "filter_spam", True),
                    help="Descarta automáticamente mensajes de spam, promociones VIP y enlaces publicitarios."
                )
                CONFIG.live.only_trading_signals = st.checkbox(
                    "🎯 Solo Señales y Actualizaciones de Trading",
                    value=getattr(CONFIG.live, "only_trading_signals", False),
                    help="Filtro estricto: solo reenvía mensajes que contengan términos de trading (BUY, SELL, SL, TP, BE)."
                )

        if st.button("💾 Guardar Parámetros de Ejecución"):
            write_config(CONFIG)
            if is_systemd:
                try:
                    subprocess.run(["systemctl", "restart", "tgcf.service"])
                except Exception:
                    pass
            st.success("Parámetros actualizados y aplicados.")

    st.markdown("---")

    # Visor de Logs
    st.subheader("📜 Registros de Actividad (Logs)")
    log_c1, log_c2 = st.columns([8, 2])
    with log_c1:
        lines_count = st.slider("Número de líneas recientes a mostrar", min_value=30, max_value=500, value=100, step=10)
    with log_c2:
        st.write("")
        st.write("")
        if st.button("🔄 Refrescar Logs", use_container_width=True):
            st.rerun()

    journal_logs = ""
    if os.name != "nt":
        try:
            res = subprocess.run(
                ["journalctl", "-u", "tgcf.service", "-n", str(lines_count), "--no-pager"],
                capture_output=True,
                text=True
            )
            journal_logs = res.stdout
        except Exception:
            pass

    if journal_logs.strip():
        st.code(journal_logs, language="log")
        st.download_button("📥 Descargar Logs de Actividad", data=journal_logs, file_name="tgcf_journal_logs.txt")
    elif os.path.exists("logs.txt"):
        try:
            with open("logs.txt", "r", encoding="utf-8", errors="ignore") as f:
                all_lines = f.readlines()
                display_lines = all_lines[-lines_count:] if len(all_lines) > lines_count else all_lines
                st.code("".join(display_lines), language="log")

            with open("logs.txt", "r", encoding="utf-8", errors="ignore") as f:
                st.download_button("📥 Descargar Archivo logs.txt", data=f.read(), file_name="tgcf_logs.txt")
        except Exception as e:
            st.error(f"Error leyendo el archivo de logs: {e}")
    else:
        st.info("No se encontraron registros aún. Inicia el servicio para generar actividad.")

    st.caption("💡 **Tip VPS:** El reenvío se ejecuta 24/7 mediante systemd: `sudo journalctl -u tgcf -f`")
