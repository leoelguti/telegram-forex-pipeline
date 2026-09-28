# 🗺️ Roadmap de Mejoras Futuras - Forex Signal Execution Pipeline

Este documento consolida las mejoras técnicas, optimizaciones y nuevas funcionalidades planificadas para evolucionar el pipeline de trading algorítmico hacia un estándar institucional y totalmente autónomo.

---

## 📌 Estado Actual del Pipeline (Base Operativa)
- **Captura con `tgcf` (Telethon):** Reenvío de canales públicos/privados al canal buffer privado con metadatos de canal `[ORIGIN_ID:...|NAME:...]`. Filtros anti-spam, normalización de mensajes editados y protección de longitud de captions de imágenes.
- **Orquestación en `n8n`:** Webhook receptor, deduplicación de señales, normalización de pares, inferencia estructurada con IA (Groq Qwen 3.8 / Llama 3), validaciones matemáticas de riesgo (SL obligatorio, coherencia de TP/SL) y división de lotaje Multi-TP.
- **Ejecución en `MetaTrader 5` (EA MQL5):** Escucha continua de Telegram Bot API, resolución dinámica de símbolos con sufijo del broker (`.pro`), ejecución de órdenes de mercado y pendientes, y registro de trades en PocketBase.
- **Auditoría en `PocketBase`:** Base de datos con historial de señales, logs de validación y métricas de rendimiento por canal.

---

## 🚀 Módulos Planificados para Futuras Iteraciones

### 1. Gestión Activa del Trade (Post-Entrada)
* **Breakeven Automático (BE):**
  - Mover automáticamente el Stop Loss al precio de apertura (`OpenPrice`) una vez que el precio alcance una ganancia predeterminada en pips (ej. +20 pips) o al tocar el Take Profit 1 (TP1).
  - Asegurar la operación libre de riesgo (*risk-free trade*).
* **Trailing Stop Dinámico:**
  - Desplazamiento progresivo del Stop Loss acompañando el avance del precio en tendencia favorable para asegurar beneficios acumulados.
* **Procesamiento de Mensajes de Actualización del Canal:**
  - Interpretar y ejecutar mensajes de seguimiento de los proveedores:
    - *"Mover SL a Entrada / Breakeven"* ➔ Modificar SL del ticket abierto en MT5.
    - *"Cerrar la mitad del lote (+30 pips)"* ➔ Cierre parcial de volumen (`OrderClosePartial`).
    - *"Cerrar todo a mercado ahora"* ➔ Cierre inmediato de la posición.
    - *"Cancelar orden limit/stop"* ➔ Borrado de orden pendiente no ejecutada.

---

### 2. Gestión de Riesgo Profesional (Position Sizing Dinámico)
* **Lotaje Automático por % de Cuenta:**
  - Sustituir el lotaje fijo por un cálculo dinámico según el balance y porcentaje de riesgo deseado por operación (ej. arriesgar exactamente el 1% del capital):
    $$\text{Lote} = \frac{\text{Balance} \times \text{Riesgo \%}}{\text{Distancia al SL en Pips} \times \text{Valor del Pip}}$$
  - Protección ante Stop Loss muy amplios (evita sobreexposición en pares volátiles como XAUUSD).
* **Circuit Breaker / Límite Diario de Pérdidas (Max Daily Drawdown):**
  - Pausa automática de apertura de nuevas operaciones si la cuenta acumula una pérdida máxima intradía (ej. -4% del balance total), protegiendo la cuenta en días de alta volatilidad o noticias de alto impacto.

---

### 3. Notificaciones y Alertas Push al Administrador
* **Bot de Notificaciones Privadas (Telegram Admin Bot):**
  - Alerta instantánea al móvil del usuario ante eventos clave:
    - 🟢 *Orden Ejecutada:* Par, tipo de orden, lotaje, precio de entrada, SL, TP y canal de origen.
    - 💰 *Take Profit / Stop Loss Alcanzado:* Resultado en USD y pips.
    - ⚠️ *Señal Descartada:* Motivo del descarte (falta de SL, publicidad, precio inválido).
    - 🔴 *Alerta Crítica:* Margen insuficiente, error de conexión o fallo de broker.

---

### 4. Reconocimiento de Señales en Imágenes (Visión / OCR)
* **Extracción de Señales desde Capturas de Gráficos:**
  - Canales que comparten capturas de pantalla de TradingView o MetaTrader sin texto en el pie de foto.
  - Integrar Llama 3.2 Vision (Groq) o un microservicio OCR para extraer niveles de Entrada, SL y TP dibujados en la imagen cuando el texto del pie de foto esté ausente.

---

### 5. Filtrado Automático por Calidad y Rentabilidad de Canales
* **Whitelist / Blacklist Dinámica con PocketBase:**
  - Evaluación continua del *Win Rate* y *Profit Factor* de cada canal registrado.
  - Si un canal acumula un porcentaje de acierto inferior al 40% o un balance neto negativo en sus últimos $N$ trades, el pipeline actualizará automáticamente su estado a `pausado` en PocketBase, descartando sus señales en n8n sin intervención manual.

---

### 6. Operativa 24/5 Ininterrumpida en la Nube
* **Migración de MetaTrader 5 al VPS:**
  - Trasladar el terminal MT5 desde la máquina Windows local hacia el entorno en la nube (VPS Windows o Linux con Wine/Docker).
  - Elimina la dependencia de la laptop personal y garantiza ejecución constante 24/5 con latencia ultra-baja hacia el broker.

---

## 📋 Lista de Tareas (Backlog)

- [ ] **Módulo 1:** Implementar función `ApplyBreakeven()` y trailing stop en `ForexSignalExecutionEA.mq5`.
- [ ] **Módulo 2:** Implementar parser para acciones `MODIFY_SL`, `CLOSE_PARTIAL`, `CLOSE_NOW`, `CANCEL` en n8n y EA.
- [ ] **Módulo 3:** Agregar cálculo de lotaje por riesgo en base a distancia SL en `Common.mqh`.
- [ ] **Módulo 4:** Crear bot de alertas administrativas vía webhook en n8n hacia chat privado de Telegram.
- [ ] **Módulo 5:** Agregar paso de visión/OCR para señales en imágenes sin pie de foto.
- [ ] **Módulo 6:** Implementar auto-pausa de canales perdedores en `audit_ranking_canales.py`.
- [ ] **Módulo 7:** Despliegue de MT5 en VPS en la nube.
