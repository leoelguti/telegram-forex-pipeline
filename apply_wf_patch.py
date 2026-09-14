import sqlite3
import json

db_path = 'n8n/.n8n/.n8n/database.sqlite'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("SELECT nodes FROM workflow_entity WHERE id = '6vqAZMbw2e8cxpaD'")
nodes = json.loads(c.fetchone()[0])

new_risk_code = """const prefilter = $('Pre-Filtro').first().json;
const rawMessage = prefilter.raw_message || '';
const channelId = prefilter.channel_id || '';
const msgId = prefilter.telegram_msg_id || '';

let parsed = null;
let parserSource = 'GROQ';

// 1. Intentar parsear respuesta de Groq
try {
  const groqResp = $input.first()?.json;
  if (groqResp && groqResp.choices && groqResp.choices[0]?.message?.content) {
    parsed = JSON.parse(groqResp.choices[0].message.content);
  }
} catch (e) {
  parsed = null;
}

// 2. Si Groq fallo (403, error, red), usar Smart Regex Fallback
if (!parsed || !parsed.action || !parsed.symbol) {
  const upper = rawMessage.toUpperCase();
  
  // Extraer accion
  const actMatch = upper.match(/\\b(BUY|SELL|COMPRA|VENTA)\\b/);
  const action = actMatch ? (actMatch[1] === 'COMPRA' ? 'BUY' : actMatch[1] === 'VENTA' ? 'SELL' : actMatch[1]) : null;
  
  // Extraer simbolo
  let symbol = null;
  const symPatterns = [
    /\\b(GOLD|XAUUSD|SILVER|XAGUSD|EURUSD|GBPUSD|USDJPY|USDCAD|AUDUSD|NZDUSD|USDCHF|EURJPY|GBPJPY|US30|NAS100|USTEC|SPX500|GER30|GER40|DAX|OIL|WTI|USOUSD)\\b/,
    /\\b([A-Z]{6})\\b/
  ];
  for (const sp of symPatterns) {
    const sm = upper.match(sp);
    if (sm) {
      symbol = sm[1];
      break;
    }
  }
  
  // Extraer SL
  let stopLoss = null;
  const slMatch = upper.match(/(?:SL|STOP\\s*LOSS|STOP)\\s*[:=\\-]?\\s*([0-9]+(?:\\.[0-9]+)?)/);
  if (slMatch) {
    stopLoss = parseFloat(slMatch[1]);
  }
  
  // Extraer TP
  let takeProfit = null;
  const tpMatch = upper.match(/(?:TP1?|TAKE\\s*PROFIT|TARGET)\\s*[:=\\-]?\\s*([0-9]+(?:\\.[0-9]+)?)/);
  if (tpMatch) {
    takeProfit = parseFloat(tpMatch[1]);
  }
  
  // Extraer Entry
  let entry = null;
  const entryMatch = upper.match(/(?:ENTRY|ENTRADA|AT|@|PRICE)?\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(?:SL|STOP)/);
  if (entryMatch) {
    entry = parseFloat(entryMatch[1]);
  }
  
  if (action && symbol && stopLoss && !isNaN(stopLoss)) {
    parsed = {
      is_signal: true,
      action: action,
      symbol: symbol,
      entry: entry,
      stop_loss: stopLoss,
      take_profit: isNaN(takeProfit) ? 0 : takeProfit,
      notes: 'Smart Regex Fallback'
    };
    parserSource = 'REGEX_FALLBACK';
  }
}

if (!parsed || !parsed.is_signal || !parsed.action || !parsed.symbol) {
  return [{
    json: {
      execute: false,
      status: 'DESCARTADO',
      reason: 'No se pudo extraer una orden valida (accion, simbolo y SL requeridos)',
      channel_id: channelId,
      telegram_msg_id: msgId,
      raw_message: rawMessage,
      json_extraido: parsed
    }
  }];
}

const action = String(parsed.action).toUpperCase();
const stopLoss = parseFloat(parsed.stop_loss);
const takeProfit = parseFloat(parsed.take_profit);
const entry = parsed.entry ? parseFloat(parsed.entry) : null;

// Regla 1: Stop Loss Obligatorio
if (isNaN(stopLoss) || stopLoss <= 0) {
  return [{
    json: {
      execute: false,
      status: 'RECHAZO_RIESGO',
      reason: 'Stop Loss OBLIGATORIO ausente o invalido (<= 0)',
      channel_id: channelId,
      telegram_msg_id: msgId,
      raw_message: rawMessage,
      json_extraido: parsed
    }
  }];
}

// Regla 2: Coherencia Matematica
if (entry && !isNaN(entry) && entry > 0) {
  if (action === 'BUY') {
    if (stopLoss >= entry) {
      return [{
        json: {
          execute: false,
          status: 'RECHAZO_RIESGO',
          reason: `Incoherencia BUY: SL (${stopLoss}) debe ser menor que Entry (${entry})`,
          channel_id: channelId,
          telegram_msg_id: msgId,
          raw_message: rawMessage,
          json_extraido: parsed
        }
      }];
    }
    if (!isNaN(takeProfit) && takeProfit > 0 && takeProfit <= entry) {
      return [{
        json: {
          execute: false,
          status: 'RECHAZO_RIESGO',
          reason: `Incoherencia BUY: TP (${takeProfit}) debe ser mayor que Entry (${entry})`,
          channel_id: channelId,
          telegram_msg_id: msgId,
          raw_message: rawMessage,
          json_extraido: parsed
        }
      }];
    }
  } else if (action === 'SELL') {
    if (stopLoss <= entry) {
      return [{
        json: {
          execute: false,
          status: 'RECHAZO_RIESGO',
          reason: `Incoherencia SELL: SL (${stopLoss}) debe ser mayor que Entry (${entry})`,
          channel_id: channelId,
          telegram_msg_id: msgId,
          raw_message: rawMessage,
          json_extraido: parsed
        }
      }];
    }
    if (!isNaN(takeProfit) && takeProfit > 0 && takeProfit >= entry) {
      return [{
        json: {
          execute: false,
          status: 'RECHAZO_RIESGO',
          reason: `Incoherencia SELL: TP (${takeProfit}) debe ser menor que Entry (${entry})`,
          channel_id: channelId,
          telegram_msg_id: msgId,
          raw_message: rawMessage,
          json_extraido: parsed
        }
      }];
    }
  }
}

// Regla 3: Normalizacion de Simbolo
let symbol = String(parsed.symbol).toUpperCase().replace(/[^A-Z0-9]/g, '');
if (symbol === 'GOLD') symbol = 'XAUUSD';
if (symbol === 'SILVER') symbol = 'XAGUSD';
if (symbol === 'OIL' || symbol === 'WTI') symbol = 'USOUSD';
if (symbol === 'NASDAQ' || symbol === 'NAS100') symbol = 'USTEC';
if (symbol === 'DOW' || symbol === 'US30') symbol = 'US30';

return [{
  json: {
    execute: true,
    status: 'ENVIADO_MT5',
    reason: `OK (${parserSource})`,
    channel_id: channelId,
    telegram_msg_id: msgId,
    raw_message: rawMessage,
    json_extraido: parsed,
    order: {
      execute: true,
      symbol: symbol,
      action: action,
      entry: entry,
      stop_loss: stopLoss,
      take_profit: isNaN(takeProfit) ? 0 : takeProfit,
      lot: 0.01,
      reason: `OK (${parserSource})`
    }
  }
}];"""

for n in nodes:
    if n.get('name') == 'Groq Llama 3.3':
        n['continueOnFail'] = True
        print("Updated Groq Llama 3.3 with continueOnFail=True")
    elif n.get('name') == 'Validacion de Riesgo':
        n['parameters']['jsCode'] = new_risk_code
        print("Updated Validacion de Riesgo with Smart Regex Fallback")

c.execute("UPDATE workflow_entity SET nodes = ? WHERE id = '6vqAZMbw2e8cxpaD'", (json.dumps(nodes),))
conn.commit()
conn.close()
print("Workflow updated successfully in sqlite database!")
