import json
import time
import os
import subprocess
import streamlit as st

from tgcf.config import CONFIG, Forward, read_config, write_config
from tgcf.web_ui.password import check_password
from tgcf.web_ui.utils import get_list, get_string, hide_st, switch_theme

CONFIG = read_config()

st.set_page_config(
    page_title="Gestión de Canales - tgcf",
    page_icon="🔗",
    layout="wide",
)
hide_st(st)
switch_theme(st, CONFIG)

# Custom CSS para UX moderna y rápida
st.markdown("""
<style>
    .channel-card {
        background-color: rgba(255, 255, 255, 0.03);
        border: 1px solid rgba(255, 255, 255, 0.1);
        border-radius: 8px;
        padding: 16px;
        margin-bottom: 12px;
        transition: border-color 0.2s;
    }
    .channel-card:hover {
        border-color: rgba(0, 210, 106, 0.4);
    }
    .status-badge-active {
        display: inline-block;
        padding: 3px 8px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: 700;
        background-color: rgba(0, 210, 106, 0.15);
        color: #00d26a;
        border: 1px solid rgba(0, 210, 106, 0.3);
    }
    .status-badge-paused {
        display: inline-block;
        padding: 3px 8px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: 700;
        background-color: rgba(160, 174, 192, 0.15);
        color: #a0aec0;
        border: 1px solid rgba(160, 174, 192, 0.3);
    }
    .stat-box {
        background-color: rgba(255, 255, 255, 0.04);
        border-radius: 8px;
        padding: 12px;
        text-align: center;
        border: 1px solid rgba(255, 255, 255, 0.08);
    }
    .stat-val {
        font-size: 22px;
        font-weight: bold;
    }
    .stat-lbl {
        font-size: 12px;
        color: #a0aec0;
        text-transform: uppercase;
    }
</style>
""", unsafe_allow_html=True)


def restart_tgcf_service():
    """Reinicia el servicio systemd de tgcf si se ejecuta en Linux."""
    if os.name != "nt":
        try:
            subprocess.run(["systemctl", "restart", "tgcf.service"], capture_output=True)
            return True
        except Exception:
            return False
    return False


def get_default_destination():
    """Detecta el canal destino predominante en las conexiones existentes."""
    if CONFIG.forwards:
        for f in CONFIG.forwards:
            if f.dest and len(f.dest) > 0 and str(f.dest[0]).strip():
                return str(f.dest[0]).strip()
    return "https://t.me/+G-9R9xrPIEwxMThh"


def parse_bulk_channels(text, default_dest):
    """
    Parsea una lista de canales pegados en lote.
    Admite formatos:
      - https://t.me/canal
      - @canal
      - -100123456789 | Nombre Canal
      - Nombre Canal, https://t.me/canal
    """
    imported = []
    lines = text.strip().splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        src = ""
        name = ""

        if "|" in line:
            parts = [p.strip() for p in line.split("|", 1)]
            if parts[0].startswith("http") or parts[0].startswith("-") or parts[0].startswith("@"):
                src, name = parts[0], parts[1]
            else:
                name, src = parts[0], parts[1]
        elif "," in line:
            parts = [p.strip() for p in line.split(",", 1)]
            if parts[0].startswith("http") or parts[0].startswith("-") or parts[0].startswith("@"):
                src, name = parts[0], parts[1]
            else:
                name, src = parts[0], parts[1]
        else:
            src = line
            if "t.me/" in src:
                clean_name = src.split("t.me/")[-1].replace("+", "").strip("/")
                name = clean_name.replace("_", " ").title()
            elif src.startswith("@"):
                name = src[1:].replace("_", " ").title()
            else:
                name = f"Canal {src}"

        # Limpiar source si es número entero
        clean_src = src.strip()
        if (clean_src.startswith("-") and clean_src[1:].isdigit()) or clean_src.isdigit():
            src_val = int(clean_src)
        else:
            src_val = clean_src

        clean_name = name.strip()[:31] if name.strip() else f"Canal #{len(CONFIG.forwards) + len(imported) + 1}"

        fwd = Forward(
            con_name=clean_name,
            use_this=True,
            source=src_val,
            dest=[default_dest] if default_dest else [],
            offset=0,
            end=0
        )
        imported.append(fwd)
    return imported


if check_password(st):
    st.title("🔗 Gestión de Canales de Señales")
    st.caption("Configura canales de origen ilimitados, importación masiva en lote y enrutamiento hacia MetaTrader 5.")

    total_count = len(CONFIG.forwards)
    active_count = sum(1 for f in CONFIG.forwards if f.use_this)
    paused_count = total_count - active_count
    default_dest = get_default_destination()

    # --- BARRA DE MÉTRICAS Y RESUMEN ---
    m1, m2, m3, m4 = st.columns(4)
    with m1:
        st.markdown(f'<div class="stat-box"><div class="stat-val" style="color: #60a5fa;">{total_count}</div><div class="stat-lbl">Canales Totales</div></div>', unsafe_allow_html=True)
    with m2:
        st.markdown(f'<div class="stat-box"><div class="stat-val" style="color: #00d26a;">{active_count}</div><div class="stat-lbl">🟢 Activos</div></div>', unsafe_allow_html=True)
    with m3:
        st.markdown(f'<div class="stat-box"><div class="stat-val" style="color: #a0aec0;">{paused_count}</div><div class="stat-lbl">⚪ Pausados</div></div>', unsafe_allow_html=True)
    with m4:
        st.markdown(f'<div class="stat-box"><div class="stat-val" style="color: #fbbf24; font-size: 15px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{default_dest}</div><div class="stat-lbl">🎯 Destino MT5</div></div>', unsafe_allow_html=True)

    st.write("")

    # --- BARRA DE ACCIONES GLOBALES RÁPIDAS ---
    st.subheader("⚡ Acciones Rápidas")
    act_col1, act_col2, act_col3, act_col4 = st.columns(4)
    
    with act_col1:
        if st.button("🟢 Activar Todos", use_container_width=True, help="Habilita todos los canales"):
            for f in CONFIG.forwards:
                f.use_this = True
            write_config(CONFIG)
            restart_tgcf_service()
            st.success("¡Todos los canales fueron activados!")
            time.sleep(0.5)
            st.rerun()

    with act_col2:
        if st.button("⚪ Pausar Todos", use_container_width=True, help="Pausa todos los canales (ideal antes de noticias)"):
            for f in CONFIG.forwards:
                f.use_this = False
            write_config(CONFIG)
            restart_tgcf_service()
            st.warning("Todos los canales fueron pausados temporalmente.")
            time.sleep(0.5)
            st.rerun()

    with act_col3:
        if st.button("➕ Agregar 1 Canal Manual", use_container_width=True):
            new_fwd = Forward(
                con_name=f"Canal #{total_count + 1}",
                use_this=True,
                source="",
                dest=[default_dest] if default_dest else [],
                offset=0,
                end=0
            )
            CONFIG.forwards.insert(0, new_fwd)
            write_config(CONFIG)
            st.success("Nuevo canal agregado al inicio.")
            time.sleep(0.5)
            st.rerun()

    with act_col4:
        save_top = st.button("💾 Guardar y Aplicar", type="primary", use_container_width=True)

    st.markdown("---")

    # --- SECCIÓN 1: CANAL DESTINO GLOBAL ---
    with st.expander("🎯 Canal de Destino Global (Donde MT5 recibe las señales)", expanded=False):
        st.markdown(
            "En lugar de configurar el canal de destino 1 por 1, define aquí tu canal privado de MT5. "
            "Podrás aplicarlo a **todos los canales existentes y nuevos** con un solo clic."
        )
        c_dest_in, c_dest_btn = st.columns([7, 3])
        with c_dest_in:
            global_dest_input = st.text_input(
                "Enlace o ID numérico del canal privado de MT5:",
                value=default_dest,
                key="global_dest_input",
                help="Ejemplo: https://t.me/+G-9R9xrPIEwxMThh o -1003984394749"
            ).strip()
        with c_dest_btn:
            st.write("")
            st.write("")
            if st.button("⚡ Aplicar Destino a Todos", use_container_width=True):
                if global_dest_input:
                    for f in CONFIG.forwards:
                        f.dest = [global_dest_input]
                    write_config(CONFIG)
                    restart_tgcf_service()
                    st.success(f"Destino actualizado en los {total_count} canales.")
                    time.sleep(0.5)
                    st.rerun()

    # --- SECCIÓN 2: CARGA MASIVA DE CANALES (BULK IMPORT) ---
    with st.expander("📥 Carga Masiva de Canales (Pega decenas de canales a la vez)", expanded=(total_count == 0)):
        st.markdown("""
        **¿Tienes una lista de canales para agregar?** Pégalos aquí directamente sin hacerlo uno a uno.
        
        *Formatos admitidos (un canal por línea):*
        - `https://t.me/elitetrading_signals`
        - `@forex_vip_channel`
        - `-1001207746934 | XAUUSD Signals VIP`
        - `Scalping Gold, https://t.me/scalpinggold`
        """)
        bulk_text = st.text_area(
            "Pega tu lista de canales aquí:",
            height=130,
            placeholder="https://t.me/canal1\n-1001207746934 | Oro VIP\n@canal_forex\n..."
        )
        b_c1, b_c2 = st.columns([3, 7])
        with b_c1:
            if st.button("🚀 Importar Canales en Lote", type="primary", use_container_width=True):
                if bulk_text.strip():
                    dest_to_use = global_dest_input if 'global_dest_input' in locals() and global_dest_input else default_dest
                    new_channels = parse_bulk_channels(bulk_text, dest_to_use)
                    if new_channels:
                        # Evitar fuentes duplicadas exactas
                        existing_sources = {str(f.source).strip() for f in CONFIG.forwards}
                        added_count = 0
                        for nc in new_channels:
                            if str(nc.source).strip() not in existing_sources:
                                CONFIG.forwards.append(nc)
                                existing_sources.add(str(nc.source).strip())
                                added_count += 1
                        write_config(CONFIG)
                        restart_tgcf_service()
                        st.success(f"✅ ¡Se importaron {added_count} canales nuevos exitosamente! El pipeline se actualizó.")
                        time.sleep(1)
                        st.rerun()
                    else:
                        st.warning("No se detectaron canales válidos en el texto pegado.")
                else:
                    st.info("Pega al menos un enlace o ID de canal en el cuadro de texto.")

    st.markdown("---")

    # --- SECCIÓN 3: LISTADO DE CANALES CON BUSCADOR Y FILTROS ---
    st.subheader(f"📋 Canales Conectados ({total_count})")

    fil_c1, fil_c2, fil_c3 = st.columns([5, 3, 2])
    with fil_c1:
        search_query = st.text_input("🔍 Buscar canal por nombre, ID o enlace...", value="", key="search_filter").strip().lower()
    with fil_c2:
        filter_status = st.selectbox("Filtrar por estado:", ["Todos", "Solo Activos (🟢)", "Solo Pausados (⚪)"], index=0)
    with fil_c3:
        st.write("")
        st.write("")
        save_mid = st.button("💾 Guardar Todo", type="primary", key="save_mid_btn", use_container_width=True)

    # Filtrar lista para visualización
    indices_to_show = []
    for idx, fwd in enumerate(CONFIG.forwards):
        # Filtro de estado
        if filter_status == "Solo Activos (🟢)" and not fwd.use_this:
            continue
        if filter_status == "Solo Pausados (⚪)" and fwd.use_this:
            continue
        # Filtro de búsqueda
        if search_query:
            match_name = search_query in str(fwd.con_name).lower()
            match_src = search_query in str(fwd.source).lower()
            if not (match_name or match_src):
                continue
        indices_to_show.append(idx)

    st.caption(f"Mostrando {len(indices_to_show)} de {total_count} canales.")

    if not indices_to_show:
        if total_count == 0:
            st.info("No hay canales configurados aún. Utiliza la sección de **Carga Masiva** arriba para agregar tus primeros canales.")
        else:
            st.warning("Ningún canal coincide con los criterios de búsqueda.")
    else:
        # Renderizado de cada canal en tarjeta limpia y compacta
        for pos, real_idx in enumerate(indices_to_show):
            fwd = CONFIG.forwards[real_idx]
            con_num = real_idx + 1

            with st.container():
                st.markdown('<div class="channel-card">', unsafe_allow_html=True)
                
                # Fila superior de la tarjeta: Estado, Nombre rápido y botón de eliminar
                top_c1, top_c2, top_c3 = st.columns([1, 8, 1])
                with top_c1:
                    fwd.use_this = st.checkbox(
                        "Activo",
                        value=fwd.use_this,
                        key=f"active_{real_idx}",
                        help="Marca para activar el reenvío de señales de este canal."
                    )
                with top_c2:
                    status_badge = '<span class="status-badge-active">🟢 ACTIVO</span>' if fwd.use_this else '<span class="status-badge-paused">⚪ PAUSADO</span>'
                    display_title = fwd.con_name if fwd.con_name else f"Canal #{con_num}"
                    st.markdown(f"**#{con_num} — {display_title}** &nbsp; {status_badge}", unsafe_allow_html=True)
                with top_c3:
                    if st.button("🗑️", key=f"del_btn_{real_idx}", help=f"Eliminar canal #{con_num}"):
                        del CONFIG.forwards[real_idx]
                        write_config(CONFIG)
                        restart_tgcf_service()
                        st.success(f"Canal #{con_num} eliminado.")
                        time.sleep(0.3)
                        st.rerun()

                # Fila de edición principal: Nombre MT5, Origen, Destino
                ed_c1, ed_c2, ed_c3 = st.columns([4, 4, 4])
                with ed_c1:
                    fwd.con_name = st.text_input(
                        "Nombre / Comentario MT5 (máx 31 chars):",
                        value=fwd.con_name,
                        key=f"name_in_{real_idx}",
                        help="Este nombre aparecerá en el comentario de la orden en MetaTrader 5."
                    ).strip()[:31]

                with ed_c2:
                    raw_src = st.text_input(
                        "Canal Origen (Link o ID):",
                        value=str(fwd.source),
                        key=f"src_in_{real_idx}",
                        help="Ej: https://t.me/elitetrading_signals o -1001207746934"
                    ).strip()
                    # Convertir a entero si corresponde
                    if (raw_src.startswith("-") and raw_src[1:].isdigit()) or raw_src.isdigit():
                        fwd.source = int(raw_src)
                    else:
                        fwd.source = raw_src

                with ed_c3:
                    curr_dest = get_string(fwd.dest).strip() if fwd.dest else default_dest
                    dest_in = st.text_input(
                        "Canal Destino MT5:",
                        value=curr_dest,
                        key=f"dest_in_{real_idx}",
                        help="Canal privado hacia donde se reenvía la señal."
                    ).strip()
                    fwd.dest = get_list(dest_in) if dest_in else [default_dest]

                # Opciones avanzadas colapsadas (Offset, End ID)
                with st.expander(f"⚙️ Opciones avanzadas (Offset/Histórico) - Canal #{con_num}", expanded=False):
                    av_c1, av_c2 = st.columns(2)
                    with av_c1:
                        fwd.offset = int(st.text_input("Offset ID (Mensaje inicial)", value=str(fwd.offset), key=f"off_{real_idx}"))
                    with av_c2:
                        fwd.end = int(st.text_input("End ID (0 = ilimitado)", value=str(fwd.end), key=f"end_{real_idx}"))

                st.markdown('</div>', unsafe_allow_html=True)

    # --- BOTÓN DE GUARDADO PRINCIPAL AL FINAL ---
    st.markdown("---")
    save_bot1, save_bot2 = st.columns([4, 8])
    with save_bot1:
        save_bottom = st.button("💾 Guardar Todos los Cambios", type="primary", use_container_width=True, key="save_bottom_btn")
    with save_bot2:
        st.caption("Al guardar, el archivo `tgcf.config.json` se actualiza y el servicio de reenvío en la VPS se reinicia automáticamente.")

    if save_top or save_mid or save_bottom:
        write_config(CONFIG)
        restarted = restart_tgcf_service()
        if restarted:
            st.success("✅ ¡Configuración guardada y servicio tgcf reiniciado exitosamente en el VPS!")
        else:
            st.success("✅ ¡Configuración guardada exitosamente!")
        time.sleep(0.5)
        st.rerun()

    # --- SECCIÓN 4: HERRAMIENTAS DE MANTENIMIENTO Y RESPALDO ---
    with st.expander("🛠️ Herramientas de Mantenimiento y Respaldo", expanded=False):
        b1, b2 = st.columns(2)
        with b1:
            st.markdown("##### 📥 Respaldo de Canales")
            st.caption("Descarga una copia de seguridad en formato JSON de todas tus conexiones configuradas.")
            forwards_json = json.dumps([f.dict() for f in CONFIG.forwards], indent=2, ensure_ascii=False)
            st.download_button(
                "📥 Descargar Respaldo (channels_backup.json)",
                data=forwards_json,
                file_name="tgcf_channels_backup.json",
                mime="application/json",
                use_container_width=True
            )
        with b2:
            st.markdown("##### 🗑️ Limpieza en Lote")
            st.caption("Elimina de una sola vez todos los canales que se encuentren marcados como pausados.")
            if st.button("🗑️ Eliminar Canales Pausados", type="secondary", use_container_width=True):
                CONFIG.forwards = [f for f in CONFIG.forwards if f.use_this]
                write_config(CONFIG)
                restart_tgcf_service()
                st.success("Se eliminaron los canales pausados.")
                time.sleep(0.5)
                st.rerun()
