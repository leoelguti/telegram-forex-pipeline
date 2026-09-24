#!/usr/bin/env python3
"""
Script de Auditoría y Ranking de Canales en Tiempo Real.
Consulta la telemetría de PocketBase para evaluar el rendimiento de cada canal origen.
"""

import json
import os
import sys
import urllib.request

# Forzar codificación UTF-8 en consola
sys.stdout.reconfigure(encoding="utf-8")

PB_URL = os.environ.get("POCKETBASE_URL", "http://209.145.54.168:8090")


def query_pb(endpoint):
    url = f"{PB_URL}/api/{endpoint}"
    req = urllib.request.Request(url, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            data = json.loads(r.read().decode("utf-8"))
            return data.get("items", []) if isinstance(data, dict) else []
    except Exception as e:
        print(f"Error consultando {endpoint}: {e}")
        return []


def main():
    print("=" * 80)
    print("   📊 INFORME DE INTELIGENCIA Y RANKING DE CANALES (POCKETBASE TELEMETRIA)")
    print("=" * 80)
    print(f"Endpoint: {PB_URL}\n")

    trades = query_pb("collections/trades_metricas/records?perPage=500")
    canales = query_pb("collections/canales_fuente/records?perPage=100")
    logs = query_pb("collections/logs_mensajes/records?perPage=500")

    # Mapeo de nombres
    chan_names = {}
    chan_status = {}
    for c in canales:
        cid = str(c.get("channel_id", "")).strip()
        cname = str(c.get("nombre", "")).strip()
        est = str(c.get("estado", "activo")).strip()
        if cid:
            chan_names[cid] = cname
            chan_status[cid] = est

    # Métricas Globales
    closed_trades = [t for t in trades if t.get("estado_trade") == "CERRADO"]
    open_trades = [t for t in trades if t.get("estado_trade") == "ABIERTO"]

    total_closed = len(closed_trades)
    wins = [t for t in closed_trades if float(t.get("profit_usd", 0) or 0) > 0]
    losses = [t for t in closed_trades if float(t.get("profit_usd", 0) or 0) < 0]
    be = [t for t in closed_trades if float(t.get("profit_usd", 0) or 0) == 0]

    net_pnl = sum(float(t.get("profit_usd", 0) or 0) for t in closed_trades)
    net_pips = sum(float(t.get("pips", 0) or 0) for t in closed_trades)
    win_rate = (len(wins) / total_closed * 100.0) if total_closed > 0 else 0.0

    gross_win = sum(float(t.get("profit_usd", 0) or 0) for t in wins)
    gross_loss = abs(sum(float(t.get("profit_usd", 0) or 0) for t in losses))
    profit_factor = (
        (gross_win / gross_loss)
        if gross_loss > 0
        else (gross_win if gross_win > 0 else 1.0)
    )

    print("--- RESUMEN GLOBAL DEL PORTAFOLIO ---")
    pnl_sign = "+" if net_pnl >= 0 else ""
    pips_sign = "+" if net_pips >= 0 else ""
    print(f"  • Beneficio Neto:     {pnl_sign}${net_pnl:.2f} USD")
    print(f"  • Pips Totales:       {pips_sign}{net_pips:.1f} pips")
    print(
        f"  • Tasa de Acierto:    {win_rate:.1f}% ({len(wins)}W / {len(losses)}L / {len(be)}BE)"
    )
    print(f"  • Profit Factor:      {profit_factor:.2f}")
    print(
        f"  • Operaciones:        {total_closed} cerradas | {len(open_trades)} abiertas en MT5\n"
    )

    # Ranking por Canal
    channel_agg = {}
    for c in canales:
        cid = str(c.get("channel_id", "")).strip()
        cname = str(c.get("nombre", "")).strip()
        channel_agg[cid] = {
            "nombre": cname,
            "canal_id": cid,
            "estado": c.get("estado", "activo"),
            "trades": 0,
            "wins": 0,
            "losses": 0,
            "pnl": 0.0,
            "pips": 0.0,
        }

    for t in closed_trades:
        cid = str(t.get("canal_id", "")).strip()
        matched = None
        for k in channel_agg:
            if k == cid or k in cid or cid in k:
                matched = k
                break
        if not matched:
            matched = cid
            channel_agg[matched] = {
                "nombre": chan_names.get(cid, cid),
                "canal_id": cid,
                "estado": "activo",
                "trades": 0,
                "wins": 0,
                "losses": 0,
                "pnl": 0.0,
                "pips": 0.0,
            }

        pnl_val = float(t.get("profit_usd", 0) or 0)
        pips_val = float(t.get("pips", 0) or 0)
        channel_agg[matched]["trades"] += 1
        channel_agg[matched]["pnl"] += pnl_val
        channel_agg[matched]["pips"] += pips_val
        if pnl_val > 0:
            channel_agg[matched]["wins"] += 1
        elif pnl_val < 0:
            channel_agg[matched]["losses"] += 1

    sorted_ranks = sorted(
        channel_agg.values(), key=lambda x: x["pnl"], reverse=True
    )

    print("--- RANKING DE CANALES POR RENTABILIDAD ---")
    header = f"{'#':<3} | {'Canal / Proveedor':<26} | {'Estado':<8} | {'Trades':<6} | {'WinRate':<8} | {'PnL ($ USD)':<12} | {'Pips':<9}"
    print(header)
    print("-" * len(header))

    for idx, c in enumerate(sorted_ranks):
        tot = c["trades"]
        wr = (c["wins"] / tot * 100.0) if tot > 0 else 0.0
        pnl_s = f"{'+' if c['pnl'] >= 0 else ''}${c['pnl']:.2f}"
        pips_s = f"{'+' if c['pips'] >= 0 else ''}{c['pips']:.1f}"
        est_icon = "🟢 Activo" if c["estado"] == "activo" else "⏸️ Pausado"
        name_short = (
            (c["nombre"][:24] + "..")
            if len(c["nombre"]) > 26
            else c["nombre"]
        )
        print(
            f"{idx + 1:<3} | {name_short:<26} | {est_icon:<8} | {tot:<6} | {wr:>6.1f}% | {pnl_s:>12} | {pips_s:>9}"
        )

    # Ruido vs Señal
    if logs:
        print("\n--- AUDITORIA DE CALIDAD DE SEÑAL (ANTI-RUIDO) ---")
        log_counts = {}
        for entry in logs:
            cid = str(entry.get("canal_id", "")).strip()
            cname = chan_names.get(cid, cid)
            st_val = entry.get("estado", "DESCARTADO")
            if cname not in log_counts:
                log_counts[cname] = {"total": 0, "ok": 0, "discard": 0}
            log_counts[cname]["total"] += 1
            if st_val == "ENVIADO_MT5":
                log_counts[cname]["ok"] += 1
            else:
                log_counts[cname]["discard"] += 1

        print(
            f"{'Canal':<28} | {'Mensajes':<9} | {'Señales MT5':<12} | {'Eficiencia %':<12}"
        )
        print("-" * 65)
        for cname, stats in log_counts.items():
            tot = stats["total"]
            ok = stats["ok"]
            eff = (ok / tot * 100.0) if tot > 0 else 0.0
            print(
                f"{cname[:26]:<28} | {tot:<9} | {ok:<12} | {eff:>10.1f}%"
            )

    print("=" * 80)


if __name__ == "__main__":
    main()
