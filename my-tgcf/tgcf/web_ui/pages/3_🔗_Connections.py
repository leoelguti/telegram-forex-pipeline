import time
import streamlit as st

from tgcf.config import CONFIG, Forward, read_config, write_config
from tgcf.web_ui.password import check_password
from tgcf.web_ui.utils import get_list, get_string, hide_st, switch_theme

CONFIG = read_config()

st.set_page_config(
    page_title="Conexiones de Canales - tgcf",
    page_icon="🔗",
    layout="wide",
)
hide_st(st)
switch_theme(st, CONFIG)

if check_password(st):
    st.title("🔗 Conexiones de Canales Telegram")
    st.caption("Configura los canales fuentes de señales y el canal destino privado hacia MetaTrader 5.")

    st.info(
        "💡 **Atribución Automática:** Cada mensaje reenviado incluye automáticamente la etiqueta "
        "`[ORIGIN_ID:<id>|NAME:<nombre>]`. Este identificador se registrará en **PocketBase** y "
        "se colocará en el **Comentario de la Orden en MT5**.",
        icon="ℹ️"
    )

    col_btn1, col_btn2 = st.columns([2, 8])
    with col_btn1:
        add_new = st.button("➕ Agregar Canal Nuevo", type="secondary")
        if add_new:
            new_fwd = Forward()
            new_fwd.con_name = f"Canal #{len(CONFIG.forwards) + 1}"
            if CONFIG.forwards and CONFIG.forwards[0].dest:
                new_fwd.dest = list(CONFIG.forwards[0].dest)
            CONFIG.forwards.append(new_fwd)
            write_config(CONFIG)
            st.rerun()

    num = len(CONFIG.forwards)

    if num == 0:
        st.warning("No hay conexiones configuradas actualmente. Haz clic en 'Agregar Canal Nuevo' para comenzar.")
    else:
        tab_strings = []
        for i in range(num):
            fwd = CONFIG.forwards[i]
            label = fwd.con_name if fwd.con_name else f"Canal {i+1}"
            status = "🟢" if fwd.use_this else "⚪"
            tab_strings.append(f"{status} {label}")

        tabs = st.tabs(list(tab_strings))

        for i in range(num):
            with tabs[i]:
                con = i + 1
                fwd = CONFIG.forwards[i]
                name = fwd.con_name or f"Canal {con}"

                st.subheader(f"Configuración de: {name}")

                c_meta1, c_meta2 = st.columns([3, 1])
                with c_meta1:
                    fwd.con_name = st.text_input(
                        "Nombre descriptivo del canal / señal",
                        value=fwd.con_name,
                        key=f"name_{con}",
                        help="Este nombre se usará como comentario en las órdenes de MetaTrader 5 (máx 31 caracteres)."
                    )
                with c_meta2:
                    st.write("")
                    st.write("")
                    fwd.use_this = st.checkbox(
                        "Canal Activo",
                        value=fwd.use_this,
                        key=f"use_{con}",
                        help="Si está desmarcado, los mensajes de este canal serán ignorados."
                    )

                st.markdown("---")
                c_src, c_dest = st.columns(2)
                with c_src:
                    st.markdown("##### 📥 Origen (Canal Proveedor)")
                    fwd.source = st.text_input(
                        "Enlace o ID numérico del canal origen",
                        value=str(fwd.source),
                        key=f"source_{con}",
                        help="Ejemplo: https://t.me/elitetrading_signals o -1001207746934"
                    ).strip()
                    st.caption("Solo se admite 1 canal de origen por conexión.")

                with c_dest:
                    st.markdown("##### 📤 Destino (Canal Privado MT5)")
                    dest_text = st.text_area(
                        "Enlaces o IDs de los canales destino",
                        value=get_string(fwd.dest),
                        key=f"dest_{con}",
                        help="Canal privado donde tu MetaTrader 5 lee las señales (un destino por línea)."
                    )
                    fwd.dest = get_list(dest_text)
                    st.caption("Canal destino estándar: Señales MT5 Forex.")

                with st.expander("⚙️ Opciones Avanzadas (Modo Histórico / Past)"):
                    st.caption("Permite extraer mensajes pasados de este canal si se ejecuta en modo Past.")
                    col_o1, col_o2 = st.columns(2)
                    with col_o1:
                        fwd.offset = int(
                            st.text_input(
                                "Offset ID (Mensaje inicial)",
                                value=str(fwd.offset),
                                key=f"offset_{con}",
                            )
                        )
                    with col_o2:
                        fwd.end = int(
                            st.text_input(
                                "End ID (Mensaje final, 0 para ilimitado)",
                                value=str(fwd.end),
                                key=f"end_{con}"
                            )
                        )

                with st.expander("🗑️ Eliminar Conexión", expanded=False):
                    st.warning(f"¿Estás seguro de que deseas eliminar la conexión '{name}'?", icon="⚠️")
                    if st.button(f"Confirmar Eliminación de '{name}'", key=f"del_{con}", type="secondary"):
                        del CONFIG.forwards[i]
                        write_config(CONFIG)
                        try:
                            import subprocess
                            subprocess.run(["systemctl", "restart", "tgcf.service"], capture_output=True)
                        except Exception:
                            pass
                        st.success("Conexión eliminada y servicio actualizado.")
                        time.sleep(0.5)
                        st.rerun()

        st.markdown("---")
        save_col1, save_col2 = st.columns([3, 7])
        with save_col1:
            if st.button("💾 Guardar Cambios", type="primary", use_container_width=True):
                write_config(CONFIG)
                try:
                    import subprocess
                    subprocess.run(["systemctl", "restart", "tgcf.service"], capture_output=True)
                except Exception:
                    pass
                st.success("¡Configuración guardada y servicio actualizado!")
                time.sleep(0.5)
                st.rerun()
