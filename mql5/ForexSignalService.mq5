//+------------------------------------------------------------------+
//|                                         ForexSignalService.mq5   |
//|                        Pipeline Automatizado de Senales Forex     |
//|                 Servicio MQL5 en Segundo Plano (SIN GRAFICOS)     |
//+------------------------------------------------------------------+
#property service
#property copyright "Trading Forex Signal Pipeline"
#property link      "https://github.com"
#property version   "2.00"
#property description "Servicio nativo en background de MT5. Opera todos los simbolos de forma multi-activo sin requerir ningun grafico."
#property strict

#include <Telegram.mqh>
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERACIONES Y DEFINICIONES DE RIESGO                           |
//+------------------------------------------------------------------+
enum ENUM_RISK_MODE
{
   RISK_FIXED_LOT       = 0, // Lotaje Fijo (InpDefaultLot)
   RISK_PERCENT_BALANCE = 1, // Porcentaje de Balance (% de Riesgo)
   RISK_PERCENT_EQUITY  = 2  // Porcentaje de Equidad (% de Riesgo)
};

//+------------------------------------------------------------------+
//| PARAMETROS DE CONFIGURACION DEL SERVICIO                         |
//+------------------------------------------------------------------+
input group "=== TELEGRAM CONFIGURATION ===";
input bool     InpEnableTelegram      = true;               // Habilitar escucha de Telegram Bot API
input string   InpTelegramBotToken    = "";                 // Token del Bot de Telegram (ej: 123456:ABC-DEF...)
input long     InpTelegramChatId      = 0;                  // Chat ID canal privado (0 = aceptar cualquier canal)
input int      InpUpdateIntervalSec   = 1;                  // Frecuencia de chequeo Telegram (segundos)

input group "=== PIPELINE N8N & POCKETBASE ===";
input string   InpN8nWebhookUrl       = "http://209.145.54.168:5678/webhook/signal"; // Endpoint Webhook n8n VPS
input string   InpPocketBaseUrl       = "http://209.145.54.168:8090";                // Endpoint PocketBase VPS
input bool     InpReportToPocketBase  = true;                                         // Registrar metricas en PocketBase
input bool     InpNotifyTelegramReply = false;                                        // Responder al chat de Telegram con confirmacion

input group "=== RISK & CAPITAL PROTECTION ===";
input ENUM_RISK_MODE InpRiskMode      = RISK_PERCENT_BALANCE;                         // Modo de Gestion de Riesgo
input double   InpRiskPercent         = 1.0;                                          // Porcentaje de Riesgo por Trade (ej: 1.0 = 1%)
input double   InpDefaultLot          = 0.01;                                         // Lotaje Fijo / Minimo de seguridad
input double   InpMaxLotSize          = 5.0;                                          // Lotaje Maximo Absoluto por trade
input ulong    InpMaxSpreadPoints     = 40;                                           // Spread Maximo permitido en puntos (0 = desactivado)
input double   InpMaxEntryDistancePips= 15.0;                                         // Tolerancia max al precio entrada en pips (0 = off)
input ulong    InpSlippagePoints      = 30;                                           // Desviacion / Slippage maximo en puntos
input ulong    InpMagicNumber         = 888999;                                       // Magic Number
input string   InpSymbolSuffix        = "";                                           // Sufijo del broker (ej: .m, m, .pro) vacio=auto

input group "=== TAKE PROFIT & SPLIT ORDERS ===";
input bool     InpSplitOrders          = true;                                        // Dividir lote entre multiples TPs
input int      InpMaxSplitOrders       = 3;                                           // Maximo de ordenes parciales divididas

input group "=== BREAKEVEN & TRAILING STOP ===";
input bool     InpEnableBreakeven      = true;                                        // Activar Breakeven automatico
input double   InpBreakevenTriggerPips = 20.0;                                        // Pips en ganancia para mover a Breakeven
input double   InpBreakevenLockPips    = 1.5;                                         // Pips asegurados en Breakeven (+1.5 pips)
input bool     InpEnableTrailing       = false;                                       // Trailing Stop dinamico
input double   InpTrailingDistancePips = 25.0;                                        // Distancia del Trailing en pips
input double   InpTrailingStepPips     = 5.0;                                         // Paso de actualizacion del Trailing en pips

//+------------------------------------------------------------------+
//| ESTRUCTURAS Y OBJETOS GLOBALES                                   |
//+------------------------------------------------------------------+
struct STrackedTrade
{
   ulong    ticket;
   string   pb_record_id;
   string   symbol;
   string   action;
   double   lot;
   double   open_price;
   double   sl;
   double   tp;
   string   channel_id;
   bool     is_closed;
};

CTrade               g_trade;
CPositionInfo        g_posInfo;
CHistoryOrderInfo    g_histInfo;
STrackedTrade        g_tracked_trades[];

// Declaracion adelantada
void ProcessPipelineSignal(string rawMessage, string channelId, string msgId);
void ManageOpenPositions();

//+------------------------------------------------------------------+
//| CLASE BOT PERSONALIZADA (DERIVADA DE CCustomBot)                 |
//+------------------------------------------------------------------+
class CForexSignalBot : public CCustomBot
{
private:
   long m_last_processed_id;

public:
   CForexSignalBot() : m_last_processed_id(0) {}

   virtual void ProcessMessages(void)
   {
      for(int i = 0; i < ChatsTotal(); i++)
      {
         CCustomChat* chat = m_chats.GetNodeAtIndex(i);
         if(chat == NULL) continue;
         if(chat.m_new_one.done) continue;
         
         string messageText = "";
         long msgId = 0;
         long chatId = chat.m_new_one.chat_id;
         
         if(chat.m_new_one.is_channel_post)
         {
            messageText = chat.m_new_one.channel_post_text;
            msgId = chat.m_new_one.channel_post_id;
         }
         else
         {
            messageText = chat.m_new_one.message_text;
            msgId = chat.m_new_one.message_id;
         }
         
         chat.m_new_one.done = true;
         
         if(msgId != 0 && msgId == m_last_processed_id)
            continue;
            
         if(StringLen(messageText) > 0)
         {
            m_last_processed_id = msgId;
            
            if(InpTelegramChatId != 0 && chatId != InpTelegramChatId)
               continue;
               
            ProcessPipelineSignal(messageText, IntegerToString(chatId), IntegerToString(msgId));
         }
      }
   }
};

CForexSignalBot* g_bot = NULL;

//+------------------------------------------------------------------+
//| UTILIDADES HTTP Y WEB REQUEST                                    |
//+------------------------------------------------------------------+
int HttpPost(const string url, const string jsonBody, string &responseBody, string &responseHeaders)
{
   char postData[];
   char resultData[];
   StringToCharArray(jsonBody, postData, 0, WHOLE_ARRAY, CP_UTF8);
   int dataLen = ArraySize(postData);
   if(dataLen > 0 && postData[dataLen - 1] == 0)
      ArrayResize(postData, dataLen - 1);

   string headers = "Content-Type: application/json\r\n";
   int timeout = 6000;
   
   ResetLastError();
   int res = WebRequest("POST", url, headers, timeout, postData, resultData, responseHeaders);
   if(res == -1)
   {
      int err = GetLastError();
      PrintFormat("[HTTP ERROR] WebRequest POST fallo. URL=%s Error=%d", url, err);
      if(err == 4014)
         PrintFormat("[ALERTA 4014] Agrega '%s' en Herramientas -> Opciones -> Asesores Expertos -> Permitir WebRequest.", url);
      return -1;
   }
   
   responseBody = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
   return res;
}

int HttpGet(const string url, string &responseBody, string &responseHeaders)
{
   char postData[];
   char resultData[];
   string headers = "";
   int timeout = 6000;
   
   ResetLastError();
   int res = WebRequest("GET", url, headers, timeout, postData, resultData, responseHeaders);
   if(res == -1)
   {
      int err = GetLastError();
      if(err == 4014)
         PrintFormat("[ALERTA 4014] Agrega '%s' en Herramientas -> Opciones -> Asesores Expertos -> Permitir WebRequest.", url);
      return -1;
   }
   
   responseBody = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
   return res;
}

//+------------------------------------------------------------------+
//| RESOLUCION MULTI-PAR / MULTI-ACTIVO                              |
//+------------------------------------------------------------------+
string ResolveSymbol(string symbol)
{
   StringToUpper(symbol);
   StringTrimLeft(symbol);
   StringTrimRight(symbol);
   
   bool isCustom = false;
   if(SymbolExist(symbol, isCustom))
      return symbol;
      
   if(InpSymbolSuffix != "" && SymbolExist(symbol + InpSymbolSuffix, isCustom))
      return symbol + InpSymbolSuffix;
      
   string commonSuffixes[] = {"m", ".m", ".pro", ".raw", "_i", ".ecn", "_SB"};
   for(int i = 0; i < ArraySize(commonSuffixes); i++)
   {
      if(SymbolExist(symbol + commonSuffixes[i], isCustom))
         return symbol + commonSuffixes[i];
   }
   
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string sName = SymbolName(i, false);
      string sUpper = sName;
      StringToUpper(sUpper);
      if(StringFind(sUpper, symbol) >= 0)
         return sName;
   }
   
   return "";
}

void ConfigureFillingMode(string symbol)
{
   uint fill = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fill & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| TAMANO DE PIP SEGUN INSTRUMENTO (FOREX, ORO, INDICES)            |
//+------------------------------------------------------------------+
double GetPipSize(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string symUpper = symbol;
   StringToUpper(symUpper);
   
   // Oro / XAUUSD: 1 pip = 0.10 (10 centavos)
   if(StringFind(symUpper, "XAU") >= 0 || StringFind(symUpper, "GOLD") >= 0)
      return 0.10;
      
   // Forex brokers con 3 o 5 decimales (1 pip = 10 puntos)
   if(digits == 3 || digits == 5)
      return point * 10.0;
      
   // Indices
   if(StringFind(symUpper, "US30") >= 0 || StringFind(symUpper, "NAS") >= 0 || StringFind(symUpper, "SPX") >= 0)
      return 1.0;
      
   return (point > 0.0) ? point : 0.0001;
}

//+------------------------------------------------------------------+
//| REGISTRO Y AUDITORIA EN POCKETBASE                               |
//+------------------------------------------------------------------+
void ReportTradeToPocketBase(ulong ticket, string channelId, string symbol, string action, double lot, double price, double sl, double tp)
{
   string url = InpPocketBaseUrl + "/api/collections/trades_metricas/records";
   
   CJAVal pbPayload;
   pbPayload["ticket_mt5"]     = IntegerToString(ticket);
   pbPayload["canal_id"]       = channelId;
   pbPayload["par"]            = symbol;
   pbPayload["accion"]         = action;
   pbPayload["lotaje"]         = lot;
   pbPayload["precio_entrada"] = price;
   pbPayload["stop_loss"]      = sl;
   pbPayload["take_profit"]    = tp;
   pbPayload["estado_trade"]   = "ABIERTO";
   
   string payloadStr;
   pbPayload.Serialize(payloadStr);
                                 
   string resp, headers;
   int res = HttpPost(url, payloadStr, resp, headers);
   if(res == 200 || res == 201)
   {
      CJAVal respJson;
      respJson.Deserialize(resp);
      string recId = respJson["id"].ToStr();
      PrintFormat("[POCKETBASE] Orden registrada con ID: %s (Ticket #%I64u)", recId, ticket);
      
      int sz = ArraySize(g_tracked_trades);
      ArrayResize(g_tracked_trades, sz + 1);
      g_tracked_trades[sz].ticket = ticket;
      g_tracked_trades[sz].pb_record_id = recId;
      g_tracked_trades[sz].symbol = symbol;
      g_tracked_trades[sz].action = action;
      g_tracked_trades[sz].lot = lot;
      g_tracked_trades[sz].open_price = price;
      g_tracked_trades[sz].sl = sl;
      g_tracked_trades[sz].tp = tp;
      g_tracked_trades[sz].channel_id = channelId;
      g_tracked_trades[sz].is_closed = false;
   }
   else
   {
      PrintFormat("[POCKETBASE ERROR] Status: %d Resp: %s", res, resp);
   }
}

void CheckClosedPositions()
{
   int count = ArraySize(g_tracked_trades);
   if(count == 0) return;
   
   for(int i = 0; i < count; i++)
   {
      if(g_tracked_trades[i].is_closed) continue;
      
      if(!PositionSelectByTicket(g_tracked_trades[i].ticket))
      {
         datetime from = TimeCurrent() - 86400 * 2;
         HistorySelect(from, TimeCurrent());
         
         double closePrice = 0.0;
         double profitUsd = 0.0;
         int deals = HistoryDealsTotal();
         for(int d = deals - 1; d >= 0; d--)
         {
            ulong dealTicket = HistoryDealGetTicket(d);
            if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == g_tracked_trades[i].ticket)
            {
               if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
               {
                  closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  profitUsd += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  profitUsd += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                  profitUsd += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                  break;
               }
            }
         }
         
         double pipSize = GetPipSize(g_tracked_trades[i].symbol);
         double pips = 0.0;
         if(pipSize > 0.0 && closePrice > 0.0)
         {
            if(g_tracked_trades[i].action == "BUY" || g_tracked_trades[i].action == "LONG")
               pips = (closePrice - g_tracked_trades[i].open_price) / pipSize;
            else
               pips = (g_tracked_trades[i].open_price - closePrice) / pipSize;
         }
         
         if(g_tracked_trades[i].pb_record_id != "")
         {
            string url = InpPocketBaseUrl + "/api/collections/trades_metricas/records/" + g_tracked_trades[i].pb_record_id;
            
            CJAVal patchJson;
            patchJson["precio_cierre"] = closePrice;
            patchJson["profit_usd"]    = profitUsd;
            patchJson["pips"]          = pips;
            patchJson["estado_trade"]  = "CERRADO";
            
            string patchBody;
            patchJson.Serialize(patchBody);
            
            char postData[];
            char resultData[];
            string headers = "Content-Type: application/json\r\n";
            string resHeaders;
            StringToCharArray(patchBody, postData, 0, WHOLE_ARRAY, CP_UTF8);
            int dataLen = ArraySize(postData);
            if(dataLen > 0 && postData[dataLen - 1] == 0) ArrayResize(postData, dataLen - 1);
            
            ResetLastError();
            WebRequest("PATCH", url, headers, 5000, postData, resultData, resHeaders);
            PrintFormat("[POCKETBASE] Posicion #%I64u cerrada registrada. PnL=$%.2f Pips=%.1f", 
                        g_tracked_trades[i].ticket, profitUsd, pips);
         }
         
         g_tracked_trades[i].is_closed = true;
      }
   }
}

//+------------------------------------------------------------------+
//| CALCULO DINAMICO DE LOTAJE BASADO EN RIESGO                      |
//+------------------------------------------------------------------+
double CalculateLotSize(string brokerSymbol, string action, double entryPrice, double slPrice)
{
   if(InpRiskMode == RISK_FIXED_LOT || InpRiskPercent <= 0.0)
      return InpDefaultLot;

   if(slPrice <= 0.0)
   {
      PrintFormat("[RISK SIZING] Señal sin Stop Loss. Usando lotaje fijo de seguridad: %.2f", InpDefaultLot);
      return InpDefaultLot;
   }

   double baseCapital = (InpRiskMode == RISK_PERCENT_BALANCE) ? AccountInfoDouble(ACCOUNT_BALANCE) : AccountInfoDouble(ACCOUNT_EQUITY);
   if(baseCapital <= 0.0)
      return InpDefaultLot;

   double riskMoney = baseCapital * (InpRiskPercent / 100.0);
   double slDistance = MathAbs(entryPrice - slPrice);
   if(slDistance <= 0.0)
      return InpDefaultLot;

   double tickValue = SymbolInfoDouble(brokerSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(brokerSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
   {
      PrintFormat("[RISK WARNING] Imposible obtener tick value/size para %s. Usando lotaje fijo: %.2f", brokerSymbol, InpDefaultLot);
      return InpDefaultLot;
   }

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return InpDefaultLot;

   double calculatedLot = riskMoney / lossPerLot;

   double minLot  = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_STEP);

   if(InpMaxLotSize > 0.0 && InpMaxLotSize < maxLot)
      maxLot = InpMaxLotSize;

   if(lotStep > 0.0)
      calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;

   if(calculatedLot < minLot) calculatedLot = minLot;
   if(calculatedLot > maxLot) calculatedLot = maxLot;

   PrintFormat("[RISK SIZING] %s | Capital=$%.2f | Riesgo=%.1f%% ($%.2f) | Distancia SL=%.5f | Lote=%.2f",
               brokerSymbol, baseCapital, InpRiskPercent, riskMoney, slDistance, calculatedLot);

   return calculatedLot;
}

//+------------------------------------------------------------------+
//| EJECUCION DE ORDEN EN CUALQUIER SIMBOLO                          |
//+------------------------------------------------------------------+
bool ExecuteTrade(string symbol, string action, double lot, double entry, double sl, double tp, string channelId, string msgId, string orderComment="", bool isLotPrecalculated=false)
{
   string brokerSymbol = ResolveSymbol(symbol);
   if(brokerSymbol == "")
   {
      PrintFormat("[TRADE ERROR] Simbolo '%s' no existe en el broker.", symbol);
      return false;
   }
   
   SymbolSelect(brokerSymbol, true);

   // 1. Filtro de Spread Máximo
   long currentSpread = SymbolInfoInteger(brokerSymbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && (ulong)currentSpread > InpMaxSpreadPoints)
   {
      PrintFormat("[SPREAD ALERTA] Spread actual de %s es %d puntos, superior al maximo permitido (%d). Orden cancelada por proteccion.",
                  brokerSymbol, currentSpread, InpMaxSpreadPoints);
      return false;
   }
       
   double ask = SymbolInfoDouble(brokerSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(brokerSymbol, SYMBOL_BID);
   double point = SymbolInfoDouble(brokerSymbol, SYMBOL_POINT);
   long stopsLevel = SymbolInfoInteger(brokerSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = MathMax((double)stopsLevel * point, 10.0 * point);

   StringToUpper(action);
   bool isBuy = (action == "BUY" || action == "LONG");
   bool isSell = (action == "SELL" || action == "SHORT");

   if(!isBuy && !isSell)
   {
      PrintFormat("[TRADE ERROR] Accion desconocida: %s. Solo se admiten BUY, LONG, SELL, SHORT.", action);
      return false;
   }

   // 2. Tolerancia al Precio de Entrada (Evitar entrar si el mercado ya corrio)
   if(InpMaxEntryDistancePips > 0.0 && entry > 0.0)
   {
      double pipSize = GetPipSize(brokerSymbol);
      double currentPrice = isBuy ? ask : bid;
      double diffPips = (pipSize > 0.0) ? (MathAbs(currentPrice - entry) / pipSize) : 0.0;
      
      if(diffPips > InpMaxEntryDistancePips)
      {
         PrintFormat("[ENTRADA TARDIA] Precio actual (%.5f) se alejo %.1f pips de la entrada de la senal (%.5f). Limite=%.1f pips. Orden cancelada por proteccion.",
                     currentPrice, diffPips, entry, InpMaxEntryDistancePips);
         return false;
      }
   }

   // Verificacion y adaptacion matematica de Stop Loss y Take Profit
   if(isBuy)
   {
      if(sl > 0 && sl >= (bid - minDistance))
      {
         if(entry > 0 && sl < entry)
         {
            double dist = entry - sl;
            sl = bid - dist;
            PrintFormat("[STOPS ADAPTADO] SL original (%.5f) superaba el Bid (%.5f). Ajustado por distancia: SL=%.5f", entry, bid, sl);
         }
         else
         {
            sl = bid - (minDistance * 2.0);
            PrintFormat("[STOPS ADAPTADO] SL invalido. Ajustado a distancia segura: SL=%.5f", sl);
         }
      }
      if(tp > 0 && tp <= (ask + minDistance))
      {
         if(entry > 0 && tp > entry)
         {
            double dist = tp - entry;
            tp = ask + dist;
            PrintFormat("[STOPS ADAPTADO] TP original (%.5f) estaba por debajo del Ask (%.5f). Ajustado: TP=%.5f", entry, ask, tp);
         }
         else
         {
            tp = ask + (minDistance * 4.0);
         }
      }
   }
   else if(isSell)
   {
      if(sl > 0 && sl <= (ask + minDistance))
      {
         if(entry > 0 && sl > entry)
         {
            double dist = sl - entry;
            sl = ask + dist;
            PrintFormat("[STOPS ADAPTADO] SL original (%.5f) era menor al Ask (%.5f). Ajustado por distancia: SL=%.5f", entry, ask, sl);
         }
         else
         {
            sl = ask + (minDistance * 2.0);
            PrintFormat("[STOPS ADAPTADO] SL invalido. Ajustado a distancia segura: SL=%.5f", sl);
         }
      }
      if(tp > 0 && tp >= (bid - minDistance))
      {
         if(entry > 0 && tp < entry)
         {
            double dist = entry - tp;
            tp = bid - dist;
            PrintFormat("[STOPS ADAPTADO] TP original (%.5f) superaba el Bid (%.5f). Ajustado: TP=%.5f", entry, bid, tp);
         }
         else
         {
            tp = bid - (minDistance * 4.0);
         }
      }
   }

   int digits = (int)SymbolInfoInteger(brokerSymbol, SYMBOL_DIGITS);
   if(sl > 0) sl = NormalizeDouble(sl, digits);
   if(tp > 0) tp = NormalizeDouble(tp, digits);

   // Calculo Dinamico de Lotaje por Riesgo o Normalizacion de Lote Fijo
   double entryForLot = isBuy ? ask : bid;
   double minLot  = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_STEP);
   if(InpMaxLotSize > 0.0 && InpMaxLotSize < maxLot) maxLot = InpMaxLotSize;

   if(!isLotPrecalculated)
   {
      if(InpRiskMode != RISK_FIXED_LOT)
      {
         lot = CalculateLotSize(brokerSymbol, action, entryForLot, sl);
      }
      else
      {
         if(lot <= 0.0) lot = InpDefaultLot;
         if(lot < minLot) lot = minLot;
         if(lot > maxLot) lot = maxLot;
         if(lotStep > 0.0) lot = MathFloor(lot / lotStep) * lotStep;
      }
   }
   else
   {
      if(lot < minLot) lot = minLot;
      if(lot > maxLot) lot = maxLot;
      if(lotStep > 0.0) lot = MathFloor(lot / lotStep) * lotStep;
   }
   
   ConfigureFillingMode(brokerSymbol);
   
   string comment = (orderComment != "") ? orderComment : ("Sig:" + msgId);
   if(StringLen(comment) > 31)
      comment = StringSubstr(comment, 0, 31);
   bool success = false;
   
   if(isBuy)
      success = g_trade.Buy(lot, brokerSymbol, ask, sl, tp, comment);
   else if(isSell)
      success = g_trade.Sell(lot, brokerSymbol, bid, sl, tp, comment);
   
   // Fallback ECN: Si el broker rechaza SL/TP en apertura directa (10016), abrir a mercado y modificar stops
   if(!success && g_trade.ResultRetcode() == 10016)
   {
      Print("[FALLBACK ECN] El broker no permite stops en orden a mercado. Abriendo sin stops y modificando posicion...");
      if(isBuy)
         success = g_trade.Buy(lot, brokerSymbol, ask, 0, 0, comment);
      else if(isSell)
         success = g_trade.Sell(lot, brokerSymbol, bid, 0, 0, comment);
         
      if(success)
      {
         ulong tkt = g_trade.ResultOrder();
         if(tkt == 0) tkt = g_trade.ResultDeal();
         if(sl > 0 || tp > 0)
         {
            Sleep(150);
            if(g_trade.PositionModify(tkt, sl, tp))
               PrintFormat("[FALLBACK ECN] Stops fijados con exito en posicion #%I64u: SL=%.5f TP=%.5f", tkt, sl, tp);
            else
               PrintFormat("[FALLBACK ECN] Posicion abierta #%I64u, pero fallo fijar stops: %s", tkt, g_trade.ResultRetcodeDescription());
         }
      }
   }
   
   if(!success)
   {
      PrintFormat("[TRADE FAILED] Fallo ejecucion %s en %s: Codigo %d (%s)", 
                  action, brokerSymbol, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
   }
   
   ulong ticket = g_trade.ResultOrder();
   if(ticket == 0) ticket = g_trade.ResultDeal();
   double execPrice = g_trade.ResultPrice();
   if(execPrice == 0)
      execPrice = isBuy ? SymbolInfoDouble(brokerSymbol, SYMBOL_ASK) : SymbolInfoDouble(brokerSymbol, SYMBOL_BID);
      
   PrintFormat("[TRADE EXECUTED] %s %s Lot=%.2f Ticket=#%I64u Price=%.5f SL=%.5f TP=%.5f",
               action, brokerSymbol, lot, ticket, execPrice, sl, tp);
               
   if(InpReportToPocketBase)
      ReportTradeToPocketBase(ticket, channelId, brokerSymbol, action, lot, execPrice, sl, tp);
      
   if(InpNotifyTelegramReply && g_bot != NULL && StringToInteger(channelId) != 0)
   {
      string replyMsg = StringFormat("✅ Orden Ejecutada:\n%s %s\nTicket: #%I64u\nPrecio: %.5f\nSL: %.5f | TP: %.5f",
                                     action, brokerSymbol, ticket, execPrice, sl, tp);
      g_bot.SendMessage(StringToInteger(channelId), replyMsg);
   }
      
   return true;
}

//+------------------------------------------------------------------+
//| PROCESAMIENTO CENTRAL DE LA SENAL CON N8N Y GROQ                 |
//+------------------------------------------------------------------+
void ProcessPipelineSignal(string rawMessage, string channelId, string msgId)
{
   PrintFormat("==================================================");
   PrintFormat("[SERVICE] Senal recibida Canal=%s MsgID=%s: '%s'", channelId, msgId, rawMessage);
   
   CJAVal payload;
   payload["message"]         = rawMessage;
   payload["channel_id"]      = channelId;
   payload["telegram_msg_id"] = msgId;
   
   string payloadStr;
   payload.Serialize(payloadStr);
                                 
   string n8nResp, respHeaders;
   int httpStatus = HttpPost(InpN8nWebhookUrl, payloadStr, n8nResp, respHeaders);
   if(httpStatus != 200)
   {
      PrintFormat("[SERVICE ERROR] Fallo llamada a n8n (Status %d)", httpStatus);
      return;
   }
   
   CJAVal n8nJson;
   n8nJson.Deserialize(n8nResp);
   
   bool execute = n8nJson["execute"].ToBool();
   string reason = n8nJson["reason"].ToStr();
   
   if(!execute)
   {
      PrintFormat("[SERVICE DESCARTADA] Senal descartada. Motivo: %s", reason);
      return;
   }
   
   string symbol = n8nJson["symbol"].ToStr();
   string action = n8nJson["action"].ToStr();
   double lot    = n8nJson["lot"].ToDbl();
   double entry  = n8nJson["entry"].ToDbl();
   double sl     = n8nJson["stop_loss"].ToDbl();
   double tp     = n8nJson["take_profit"].ToDbl();
   string comment = n8nJson["comment"].ToStr();
   string originChannelId = n8nJson["channel_id"].ToStr();
   if(originChannelId != "") channelId = originChannelId;
   if(comment == "") comment = "Sig:" + msgId;
   
   // Extraer lista de Take Profits (TP1, TP2, TP3...)
   double tpList[];
   if(n8nJson.FindKey("take_profits") != NULL)
   {
      int rawCount = ArraySize(n8nJson["take_profits"].m_e);
      for(int k = 0; k < rawCount; k++)
      {
         double tpVal = n8nJson["take_profits"][k].ToDbl();
         if(tpVal > 0.0)
         {
            int sz = ArraySize(tpList);
            ArrayResize(tpList, sz + 1);
            tpList[sz] = tpVal;
         }
      }
   }
   if(ArraySize(tpList) == 0 && tp > 0.0)
   {
      ArrayResize(tpList, 1);
      tpList[0] = tp;
   }
   int totalTps = ArraySize(tpList);
   
   PrintFormat("[SERVICE APROBADA] Orden verificada: %s %s Entry=%.5f SL=%.5f TPs=%d Canal=%s Comentario=%s",
               action, symbol, entry, sl, totalTps, channelId, comment);

   // Calculo de lotaje total de la senal
   string brokerSym = ResolveSymbol(symbol);
   if(brokerSym == "") brokerSym = symbol;
   
   double ask = SymbolInfoDouble(brokerSym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(brokerSym, SYMBOL_BID);
   double entryForLot = (action == "BUY" || action == "LONG") ? ask : bid;
   if(entryForLot <= 0.0) entryForLot = entry;
   
   double totalLot = (InpRiskMode != RISK_FIXED_LOT) ? 
                     CalculateLotSize(brokerSym, action, entryForLot, sl) : 
                     (lot > 0.0 ? lot : InpDefaultLot);

   // Ejecucion Split Orders si hay multiples TPs habilitados
   if(InpSplitOrders && totalTps > 1)
   {
      double minLot  = SymbolInfoDouble(brokerSym, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(brokerSym, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(brokerSym, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0.0) lotStep = 0.01;
      if(minLot <= 0.0) minLot = 0.01;
      
      int numSplits = MathMin(totalTps, InpMaxSplitOrders);
      while(numSplits > 1 && (MathFloor((totalLot / (double)numSplits) / lotStep) * lotStep) < minLot)
      {
         numSplits--;
      }
      
      if(numSplits > 1)
      {
         double splitLot = MathFloor((totalLot / (double)numSplits) / lotStep) * lotStep;
         PrintFormat("[SPLIT ORDERS] Dividiendo lote total %.2f en %d ordenes parciales de %.2f (Total TPs=%d)",
                     totalLot, numSplits, splitLot, totalTps);
                     
         for(int k = 0; k < numSplits; k++)
         {
            double orderLot = splitLot;
            // Ajustar remanente en la ultima orden parcial para no perder volumen total calculado
            if(k == numSplits - 1)
            {
               double rem = totalLot - (splitLot * (numSplits - 1));
               if(rem >= minLot && rem <= maxLot)
                  orderLot = NormalizeDouble(MathFloor(rem / lotStep) * lotStep, 2);
            }
            
            string splitComment = StringFormat("%s:TP%d", comment, k + 1);
            if(StringLen(splitComment) > 31)
               splitComment = StringSubstr(splitComment, 0, 31);
               
            ExecuteTrade(symbol, action, orderLot, entry, sl, tpList[k], channelId, msgId, splitComment, true);
         }
         return;
      }
   }
   
   // Si no se divide, ejecutar orden unica con TP1
   double singleTp = (totalTps > 0) ? tpList[0] : tp;
   ExecuteTrade(symbol, action, totalLot, entry, sl, singleTp, channelId, msgId, comment, true);
}

//+------------------------------------------------------------------+
//| GESTION AUTOMATICA DE POSICIONES ABIERTAS: BREAKEVEN & TRAILING  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!InpEnableBreakeven && !InpEnableTrailing) return;
   
   int totalPos = PositionsTotal();
   for(int i = totalPos - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      // Filtrar estrictamente por Magic Number de la estrategia
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
         
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      
      double point = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
      int digits   = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
      if(point <= 0.0) continue;
      
      double pipSize = GetPipSize(posSymbol);
      long stopsLevel = SymbolInfoInteger(posSymbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist = MathMax((double)stopsLevel * point, 10.0 * point);
      
      double ask = SymbolInfoDouble(posSymbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(posSymbol, SYMBOL_BID);
      
      if(posType == POSITION_TYPE_BUY)
      {
         double profitPips = (bid - openPrice) / pipSize;
         
         // 1. Breakeven Dinamico
         if(InpEnableBreakeven && InpBreakevenTriggerPips > 0.0)
         {
            double beSlPrice = NormalizeDouble(openPrice + (InpBreakevenLockPips * pipSize), digits);
            
            if(profitPips >= InpBreakevenTriggerPips && (currentSl < beSlPrice || currentSl == 0.0))
            {
               if((bid - beSlPrice) >= minStopDist)
               {
                  if(g_trade.PositionModify(ticket, beSlPrice, currentTp))
                  {
                     PrintFormat("[BREAKEVEN] Posicion BUY #%I64u (%s) protegida en Breakeven. Open=%.5f -> Nuevo SL=%.5f (+%.1f pips)",
                                 ticket, posSymbol, openPrice, beSlPrice, InpBreakevenLockPips);
                     currentSl = beSlPrice;
                  }
                  else
                  {
                     PrintFormat("[BREAKEVEN ERROR] Fallo modificar BUY #%I64u: %s", ticket, g_trade.ResultRetcodeDescription());
                  }
               }
            }
         }
         
         // 2. Trailing Stop Dinamico
         if(InpEnableTrailing && InpTrailingDistancePips > 0.0)
         {
            double trailDist = InpTrailingDistancePips * pipSize;
            double trailStep = InpTrailingStepPips * pipSize;
            double newSl = NormalizeDouble(bid - trailDist, digits);
            
            if(newSl > openPrice && (newSl - currentSl) >= trailStep)
            {
               if((bid - newSl) >= minStopDist)
               {
                  if(g_trade.PositionModify(ticket, newSl, currentTp))
                  {
                     PrintFormat("[TRAILING STOP] Posicion BUY #%I64u (%s) trailing actualizado. SL=%.5f -> %.5f",
                                 ticket, posSymbol, currentSl, newSl);
                  }
               }
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profitPips = (openPrice - ask) / pipSize;
         
         // 1. Breakeven Dinamico
         if(InpEnableBreakeven && InpBreakevenTriggerPips > 0.0)
         {
            double beSlPrice = NormalizeDouble(openPrice - (InpBreakevenLockPips * pipSize), digits);
            
            if(profitPips >= InpBreakevenTriggerPips && (currentSl > beSlPrice || currentSl == 0.0))
            {
               if((beSlPrice - ask) >= minStopDist)
               {
                  if(g_trade.PositionModify(ticket, beSlPrice, currentTp))
                  {
                     PrintFormat("[BREAKEVEN] Posicion SELL #%I64u (%s) protegida en Breakeven. Open=%.5f -> Nuevo SL=%.5f (+%.1f pips)",
                                 ticket, posSymbol, openPrice, beSlPrice, InpBreakevenLockPips);
                     currentSl = beSlPrice;
                  }
                  else
                  {
                     PrintFormat("[BREAKEVEN ERROR] Fallo modificar SELL #%I64u: %s", ticket, g_trade.ResultRetcodeDescription());
                  }
               }
            }
         }
         
         // 2. Trailing Stop Dinamico
         if(InpEnableTrailing && InpTrailingDistancePips > 0.0)
         {
            double trailDist = InpTrailingDistancePips * pipSize;
            double trailStep = InpTrailingStepPips * pipSize;
            double newSl = NormalizeDouble(ask + trailDist, digits);
            
            if(newSl < openPrice && (currentSl == 0.0 || (currentSl - newSl) >= trailStep))
            {
               if((newSl - ask) >= minStopDist)
               {
                  if(g_trade.PositionModify(ticket, newSl, currentTp))
                  {
                     PrintFormat("[TRAILING STOP] Posicion SELL #%I64u (%s) trailing actualizado. SL=%.5f -> %.5f",
                                 ticket, posSymbol, currentSl, newSl);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| INICIALIZACION DEL BOT DE TELEGRAM                               |
//+------------------------------------------------------------------+
bool InitializeTelegramBot()
{
   if(!InpEnableTelegram || InpTelegramBotToken == "")
   {
      Print("[TELEGRAM] Modo Telegram desactivado o token vacio.");
      return true;
   }

   g_bot = new CForexSignalBot();
   if(g_bot == NULL)
   {
      Print("[TELEGRAM ERROR] No se pudo crear instancia de CForexSignalBot.");
      return false;
   }

   int res = g_bot.Token(InpTelegramBotToken);
   if(res != 0)
   {
      PrintFormat("[TELEGRAM ERROR] Token invalido. Error: %d", res);
      delete g_bot;
      g_bot = NULL;
      return false;
   }

   res = g_bot.GetMe();
   if(res != 0)
   {
      PrintFormat("[TELEGRAM ERROR] Fallo llamada GetMe(). Error: %d", res);
      Print("[CONSEJO] Verifica si 'https://api.telegram.org' esta permitida en Herramientas -> Opciones -> Asesores Expertos.");
      delete g_bot;
      g_bot = NULL;
      return false;
   }

   PrintFormat("[TELEGRAM CONECTADO] Servicio escuchando como: @%s", g_bot.Name());
   return true;
}

//+------------------------------------------------------------------+
//| PUNTO DE ENTRADA DEL SERVICIO (SE EJECUTA EN SEGUNDO PLANO)      |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("========================================================");
   Print("   Iniciando Forex Signal SERVICE (Sin Grafico)         ");
   Print("========================================================");
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   
   InitializeTelegramBot();
   
   int sleepMs = MathMax(500, InpUpdateIntervalSec * 1000);
   
   while(!IsStopped())
   {
      // 1. Sondeo de nuevos mensajes en Telegram
      if(g_bot != NULL)
      {
         int res = g_bot.GetUpdates();
         if(res == 0)
         {
            g_bot.ProcessMessages();
         }
      }
      
      // 2. Gestion automatica de Breakeven y Trailing Stop
      ManageOpenPositions();
      
      // 3. Monitoreo de posiciones cerradas para PocketBase
      if(InpReportToPocketBase)
      {
         CheckClosedPositions();
      }
      
      Sleep(sleepMs);
   }
   
   // Cleanup al detener el servicio
   if(g_bot != NULL)
   {
      delete g_bot;
      g_bot = NULL;
   }
   
   Print("[SERVICE] Forex Signal Service detenido correctamente.");
}
//+------------------------------------------------------------------+
