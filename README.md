# 🚀 Telegram Forex Signal Execution Pipeline

Pipeline reactivo y de ultrabaja latencia para trading algorítmico en Forex. Captura señales no estructuradas desde canales de Telegram, las normaliza con IA (**Groq LLaMA 3.3**), valida reglas estrictas de gestión de riesgo, ejecuta órdenes automáticamente en **MetaTrader 5** mediante un **Expert Advisor (MQL5)** y audita logs y métricas de rendimiento en **PocketBase**.

---

## 📐 Topología y Arquitectura del Sistema

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
   ├── 2. Groq Cloud API (Llama 3.3 70B con JSON Mode) ➔ Extrae JSON estructurado
   ├── 3. Smart Regex Fallback (Garantiza redundancia ante fallas de API)
   ├── 4. Validación de Riesgo: Stop Loss obligatorio, coherencia (Buy: TP > Entry > SL)
   ├── 5. Homogeneización de pares (ej. GOLD / XAUUSD ➔ símbolo exacto del broker)
   ├── 6. Audit Log ──► PocketBase (Colección: logs_mensajes)
   └── 7. Responde al WebRequest con payload limpio (`execute: true/false`)
   │
   ▼
[MetaTrader 5: Expert Advisor]
   ├── Recibe respuesta síncrona HTTP 200 de n8n
   ├── Si `execute == true`: Ejecuta `OrderSend()` con lotaje dinámico/fijo
   └── Reporta resultado/ticket a PocketBase (Colección: trades_metricas)
```

---

## 🛠️ Componentes y Tecnologías

| Componente | Rol Técnico | Puerto / Protocolo |
| :--- | :--- | :--- |
| **`tgcf`** | Userbot en Python que reenvía en vivo mensajes de canales externos a tu canal privado sin alterar el contenido original. | Proceso local (`tgcf live`) |
| **`n8n`** | Orquestador local de flujos. Recibe la señal vía Webhook, invoca la IA, valida reglas y responde al EA. | `http://127.0.0.1:5678` |
| **`Groq Cloud API`** | Inferencia ultrarrápida (<400ms) usando modelos LLaMA 3.3 en JSON Mode para extraer: Acción, Par, Entrada, SL, TP. | HTTPS API Cloud |
| **`PocketBase`** | Backend ligero basado en SQLite para almacenar canales activos, auditoría de señales y registro de trades. | `http://127.0.0.1:8090` |
| **`MetaTrader 5 EA`** | Expert Advisor en MQL5 (`ForexSignalExecutionEA.mq5`) con interfaz visual en gráfico, ejecución síncrona y telemetría. | Terminal MT5 |

---

## 🛡️ Reglas de Negocio y Gestión de Riesgo

1. **Stop Loss Obligatorio:** Si la IA o el parser no detectan un `stop_loss` válido o es nulo, la orden se **descarta automáticamente** (`execute: false`).
2. **Coherencia Matemática:**
   - En operaciones **`BUY`**: $\text{Take Profit} > \text{Entry} > \text{Stop Loss}$
   - En operaciones **`SELL`**: $\text{Stop Loss} > \text{Entry} > \text{Take Profit}$
3. **Manejo de Casos Borde:**
   - **Precios en rango** (ej. `4464/65`): Se toma el valor promedio o entrada a mercado directa.
   - **Doble confirmación / DCA**: Se filtra para tomar únicamente la primera entrada activa.
   - **Mensajes informativos** (*"TP1 HIT"*, *"Cerrar 50%"*, etc.): El pre-filtro de n8n los identifica y descarta sin activar el motor de ejecución.

---

## 🗄️ Colecciones en PocketBase

* **`canales_fuente`**: `nombre`, `channel_id`, `estado` (activo/pausado), `riesgo_default`.
* **`logs_mensajes`**: `canal_id`, `telegram_msg_id`, `mensaje_crudo`, `json_extraido`, `estado` (`DESCARTADO`, `ERROR_PARSER`, `RECHAZO_RIESGO`, `ENVIADO_MT5`).
* **`trades_metricas`**: `ticket_mt5`, `canal_id`, `par`, `accion` (`BUY`/`SELL`), `lotaje`, `precio_entrada`, `stop_loss`, `take_profit`, `precio_cierre`, `profit_usd`, `pips`, `estado_trade` (`ABIERTO`/`CERRADO`).

Las migraciones de PocketBase se encuentran en `pocketbase/pb_migrations/` y se aplican automáticamente al iniciar.

---

## ⚙️ Instalación y Puesta en Marcha

### 1. Clonar el Repositorio
```bash
git clone https://github.com/leoelguti/telegram-forex-pipeline.git
cd telegram-forex-pipeline
```

### 2. Configurar Variables de Entorno

- **n8n:**
  Copia el archivo de ejemplo y coloca tu API Key de Groq:
  ```bash
  cp n8n/.env.example n8n/.env
  ```
  Edita `n8n/.env`:
  ```env
  GROQ_API_KEY=tu_api_key_de_groq_aqui
  ```

- **tgcf (Telegram Chat Forwarder):**
  Copia el archivo de configuración de ejemplo:
  ```bash
  cp my-tgcf/tgcf.config.example.json my-tgcf/tgcf.config.json
  ```
  Configura tus credenciales de Telegram (`API_ID`, `API_HASH`, canal origen y canal destino). Puedes generar tu sesión ejecutando `iniciar-sesion-telegram.bat`.

- **PocketBase:**
  Si no tienes el binario, ejecuta `pocketbase/download_pocketbase.bat` para descargarlo automáticamente.

### 3. Iniciar Servicios
En Windows, puedes iniciar toda la infraestructura con un solo clic:
```cmd
start-all.bat
```
Para detener todos los procesos:
```cmd
stop-all.bat
```

### 4. Configuración en MetaTrader 5
1. Copia los archivos de la carpeta `mql5/` a tu directorio de datos de MT5 (`MQL5/Experts/` y `MQL5/Include/`).
2. En MetaTrader 5, ve a **Herramientas > Opciones > Expert Advisors**:
   - Habilita **Permitir WebRequest para las URLs listadas**.
   - Agrega:
     - `https://api.telegram.org`
     - `http://127.0.0.1:5678`
     - `http://127.0.0.1:8090`
3. Arrastra `ForexSignalExecutionEA` al gráfico de tu par preferido (ej. `XAUUSD` o `EURUSD`).
4. Ingresa el Token de tu Bot de Telegram en los parámetros de entrada del EA.

---

## 🧪 Pruebas Locales

Puedes simular el envío de una señal directamente hacia n8n sin depender de Telegram:
```bash
python test_user_signal.py
```
O probar el webhook con diferentes escenarios de entrada:
```bash
python test_n8n_post.py
```

---

## ⚠️ Descargo de Responsabilidad (Disclaimer)

Este software es con fines educativos y de investigación algorítmica. El trading en los mercados de Forex y CFDs conlleva un alto nivel de riesgo para su capital debido al apalancamiento. Nunca opere con capital que no pueda permitirse perder. Asegúrese de probar ampliamente en cuentas Demo antes de utilizar en entornos reales.

---

## 📄 Licencia

Distribuido bajo la Licencia MIT. Consulta el archivo `LICENSE` para más información.
