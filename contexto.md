Aquí tienes el contexto compacto y técnico listo para colocar en el archivo de contexto o memoria de tu proyecto (por ejemplo, en un `PROJECT_CONTEXT.md` o en las instrucciones iniciales para Antigravity):

---

# PROJECT BRIEF: Telegram Forex Signal Execution Pipeline

### 1. Objetivo General

Pipeline reactivo y de baja latencia para trading algorítmico en Forex. Captura señales no estructuradas desde canales ajenos de Telegram, las normaliza con IA (Groq), ejecuta órdenes en MetaTrader 5 (Demo/Real) mediante un Expert Advisor (MQL5) y audita logs/métricas en PocketBase.

---

### 2. Topología del Stack (VPS Windows - Monomáquina)

```
[Canales Fuente Externos (Telegram)]
               │
               ▼ (MTProto - Sesión de Usuario)
[tgcf (The Telegram Chat Forwarder)] ──► Modo 'copy' hacia Canal Privado propio
               │
               ▼ (Telegram Bot API - getUpdates)
[MetaTrader 5: Expert Advisor (MQL5)]
   ├── Librería: Telegram.mqh (escucha el canal privado)
   ├── WebRequest POST ──► n8n (http://127.0.0.1:5678/webhook/signal)
   │
   ▼
[n8n (Orquestador Central)]
   ├── 1. Pre-filtro (Descarta publicidad y actualizaciones tipo "TP HIT")
   ├── 2. Groq Cloud API (Llama 3 / 3.3 con JSON Mode) ➔ Extrae JSON estructurado
   ├── 3. Validación de Riesgo: Stop Loss obligatorio, coherencia (Buy: TP > Entry > SL)
   ├── 4. Homogeneización de pares (ej. GOLD / XAUUSD ➔ símbolo exacto del broker)
   ├── 5. Audit Log ──► PocketBase (Colección: logs_mensajes)
   └── 6. Responde al WebRequest con payload limpio (`execute: true/false`)
   │
   ▼
[MetaTrader 5: Expert Advisor]
   ├── Recibe respuesta síncrona HTTP 200 de n8n
   ├── Si `execute == true`: Ejecuta `OrderSend()`
   └── Reporta resultado/ticket a n8n ──► PocketBase (Colección: trades_metricas)

```

---

### 3. Componentes y Servicios

| Componente | Rol Técnico | Configuración / Puerto |
| --- | --- | --- |
| **tgcf** | Userbot de reenvío en Python | Corre como servicio en Windows (`tgcf live`). Reenvía señales externas en tiempo real al canal privado. |
| **Canal Privado** | Buffer y monitor visual | Canal propio con un Bot de Telegram como administrador. |
| **MetaTrader 5** | Terminal + Expert Advisor | MQL5 compilado con `Telegram.mqh`. Permisos de `WebRequest` activos para `api.telegram.org` y `127.0.0.1:5678`. |
| **n8n** | Orquestador de reglas | Self-hosted en `[http://127.0.0.1:5678](http://127.0.0.1:5678)`. Recibe del EA, llama a Groq y responde la orden. |
| **Groq API** | Inferencia ultrarrápida (<400ms) | Modelos Llama 3 / 3.3. Prompt de extracción con salida en JSON estricto. |
| **PocketBase** | Base de datos local y panel web | `[http://127.0.0.1:8090](http://127.0.0.1:8090)`. Almacenamiento embebido SQLite (`pb_data`). |

---

### 4. Colecciones en PocketBase

* **`canales_fuente`**: `nombre`, `channel_id`, `estado` (activo/pausado), `riesgo_default`.
* **`logs_mensajes`**: `canal_id`, `telegram_msg_id`, `mensaje_crudo`, `json_extraido`, `estado` (DESCARTADO, ERROR_PARSER, RECHAZO_RIESGO, ENVIADO_MT5).
* **`trades_metricas`**: `ticket_mt5`, `canal_id`, `par`, `accion` (BUY/SELL), `lotaje`, `precio_entrada`, `stop_loss`, `take_profit`, `precio_cierre`, `profit_usd`, `pips`, `estado_trade` (ABIERTO/CERRADO).

---

### 5. Reglas de Negocio Inquebrantables

1. **Stop Loss Obligatorio:** Si Groq no detecta un `stop_loss` válido o es nulo, la orden se descarta automáticamente (`execute: false`).
2. **Coherencia Matemática:**
* En `BUY`: $TP > Entry$ y $SL < Entry$.
* En `SELL`: $TP < Entry$ y $SL > Entry$.


3. **Casos Borde de Entrada:**
* Rangos de entrada (ej. `4464/65`): Promediar a un solo valor o ejecutar a mercado directo.
* Múltiples órdenes/DCA (ej. `BUY NOW` + `MORE BUY`): Tomar solo la primera ejecución a mercado.
* Mensajes informativos (ej. *"Modifiqué el TP"*, *"TP HIT +40 PIPS"*): El pre-filtro de n8n los descarta sin enviar orden a MT5.