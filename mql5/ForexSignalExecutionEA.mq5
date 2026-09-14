//+------------------------------------------------------------------+
//|                                     ForexSignalExecutionEA.mq5   |
//|                        Pipeline Automatizado de Senales Forex     |
//|                    Telegram -> n8n -> Groq -> MT5 -> PocketBase  |
//|            Basado en TelegramToMT5 (https://www.mql5.com/en/code/56646) |
//+------------------------------------------------------------------+
#property copyright "Trading Forex Signal Pipeline"
#property link      "https://www.mql5.com/en/code/56646"
#property version   "2.00"
#property description "Expert Advisor reactivo para ejecucion de senales Forex desde Telegram y n8n con auditoria en PocketBase"
#property strict

#include <Telegram.mqh>
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== TELEGRAM CONFIGURATION ===";
input bool     InpEnableTelegram      = true;               // Habilitar escucha de Telegram Bot API
input string   InpTelegramBotToken    = "";                 // Token del Bot de Telegram (ej: 123456:ABC-DEF...)
input long     InpTelegramChatId      = 0;                  // Chat ID canal privado (0 = aceptar cualquier canal)
input int      InpUpdateIntervalSec   = 1;                  // Frecuencia de chequeo Telegram (segundos)

input group "=== PIPELINE N8N & POCKETBASE ===";
input string   InpN8nWebhookUrl       = "http://127.0.0.1:5678/webhook/signal"; // Endpoint Webhook n8n
input string   InpPocketBaseUrl       = "http://127.0.0.1:8090";                // Endpoint PocketBase
input bool     InpReportToPocketBase  = true;                                   // Registrar metricas en PocketBase
input bool     InpNotifyTelegramReply = false;                                  // Responder al chat de Telegram con resultado

input group "=== RISK & EXECUTION SETTINGS ===";
input ulong    InpMagicNumber         = 888999;             // Magic Number
input double   InpDefaultLot          = 0.01;               // Lotaje por defecto si la senal no define
input ulong    InpSlippagePoints      = 30;                 // Desviacion / Slippage maximo en puntos
input string   InpSymbolSuffix        = "";                 // Sufijo del broker (ej: .m, m, .pro) vacio=auto
input bool     InpShowDashboard       = true;               // Mostrar panel grafico en pantalla

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
void UpdateDashboardStatus(string text);

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
            
            // Filtro por canal opcional
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
      PrintFormat("[HTTP ERROR] WebRequest POST falló. URL=%s Error=%d", url, err);
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
//| GESTION DE SIMBOLOS Y EJECUCION DE MERCADO                       |
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
         
         double point = SymbolInfoDouble(g_tracked_trades[i].symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(g_tracked_trades[i].symbol, SYMBOL_DIGITS);
         double mult = (digits == 3 || digits == 5) ? 10.0 : 1.0;
         double pips = 0.0;
         if(point > 0 && closePrice > 0)
         {
            if(g_tracked_trades[i].action == "BUY")
               pips = (closePrice - g_tracked_trades[i].open_price) / (point * mult);
            else
               pips = (g_tracked_trades[i].open_price - closePrice) / (point * mult);
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
//| EJECUCION DE ORDEN EN METATRADER 5                               |
//+------------------------------------------------------------------+
bool ExecuteTrade(string symbol, string action, double lot, double entry, double sl, double tp, string channelId, string msgId)
{
   string brokerSymbol = ResolveSymbol(symbol);
   if(brokerSymbol == "")
   {
      PrintFormat("[TRADE ERROR] Símbolo '%s' no existe en el broker.", symbol);
      UpdateDashboardStatus("ERROR: Simbolo no existe " + symbol);
      return false;
   }
   
   SymbolSelect(brokerSymbol, true);
   
   if(lot <= 0) lot = InpDefaultLot;
   double minLot  = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(brokerSymbol, SYMBOL_VOLUME_STEP);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
      
   double ask = SymbolInfoDouble(brokerSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(brokerSymbol, SYMBOL_BID);
   double point = SymbolInfoDouble(brokerSymbol, SYMBOL_POINT);
   long stopsLevel = SymbolInfoInteger(brokerSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = MathMax((double)stopsLevel * point, 10.0 * point);

   StringToUpper(action);

   // Verificacion y adaptacion matematica de Stop Loss y Take Profit
   if(action == "BUY")
   {
      // En BUY, el SL DEBE ser estrictamente menor al Bid actual
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
      // En BUY, el TP DEBE ser estrictamente mayor al Ask actual
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
   else if(action == "SELL")
   {
      // En SELL, el SL DEBE ser estrictamente mayor al Ask actual
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
      // En SELL, el TP DEBE ser estrictamente menor al Bid actual
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
   
   ConfigureFillingMode(brokerSymbol);
   
   string comment = "Sig:" + msgId;
   bool success = false;
   
   if(action == "BUY")
      success = g_trade.Buy(lot, brokerSymbol, ask, sl, tp, comment);
   else if(action == "SELL")
      success = g_trade.Sell(lot, brokerSymbol, bid, sl, tp, comment);
   else
   {
      PrintFormat("[TRADE ERROR] Accion desconocida: %s", action);
      return false;
   }
   
   // Fallback ECN: Si el broker rechaza SL/TP en apertura directa (10016), abrir a mercado y modificar stops
   if(!success && g_trade.ResultRetcode() == 10016)
   {
      Print("[FALLBACK ECN] El broker no permite stops en orden a mercado. Abriendo sin stops y modificando posicion...");
      if(action == "BUY")
         success = g_trade.Buy(lot, brokerSymbol, ask, 0, 0, comment);
      else if(action == "SELL")
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
      UpdateDashboardStatus("FALLO ORDEN: " + g_trade.ResultRetcodeDescription());
      return false;
   }
   
   ulong ticket = g_trade.ResultOrder();
   if(ticket == 0) ticket = g_trade.ResultDeal();
   double execPrice = g_trade.ResultPrice();
   if(execPrice == 0)
      execPrice = (action == "BUY") ? SymbolInfoDouble(brokerSymbol, SYMBOL_ASK) : SymbolInfoDouble(brokerSymbol, SYMBOL_BID);
      
   PrintFormat("[TRADE EXECUTED] %s %s Lot=%.2f Ticket=#%I64u Price=%.5f SL=%.5f TP=%.5f",
               action, brokerSymbol, lot, ticket, execPrice, sl, tp);
               
   UpdateDashboardStatus("EJECUTADO: " + action + " " + brokerSymbol + " #" + IntegerToString(ticket));
   
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
   PrintFormat("[PIPELINE] Senal recibida Canal=%s MsgID=%s: '%s'", channelId, msgId, rawMessage);
   
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
      PrintFormat("[PIPELINE ERROR] Fallo llamada a n8n (Status %d)", httpStatus);
      UpdateDashboardStatus("ERROR Webhook n8n: " + IntegerToString(httpStatus));
      return;
   }
   
   CJAVal n8nJson;
   n8nJson.Deserialize(n8nResp);
   
   bool execute = n8nJson["execute"].ToBool();
   string reason = n8nJson["reason"].ToStr();
   
   if(!execute)
   {
      PrintFormat("[PIPELINE DESCARTADA] Senal descartada. Motivo: %s", reason);
      UpdateDashboardStatus("DESCARTADA: " + reason);
      return;
   }
   
   string symbol = n8nJson["symbol"].ToStr();
   string action = n8nJson["action"].ToStr();
   double lot    = n8nJson["lot"].ToDbl();
   double entry  = n8nJson["entry"].ToDbl();
   double sl     = n8nJson["stop_loss"].ToDbl();
   double tp     = n8nJson["take_profit"].ToDbl();
   
   PrintFormat("[PIPELINE APROBADA] Orden verificada: %s %s Lot=%.2f Entry=%.5f SL=%.5f TP=%.5f",
               action, symbol, lot, entry, sl, tp);
               
   ExecuteTrade(symbol, action, lot, entry, sl, tp, channelId, msgId);
}

//+------------------------------------------------------------------+
//| PANEL GRAFICO EN PANTALLA (DASHBOARD)                            |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   if(!InpShowDashboard) return;
   
   int x = 20, y = 30;
   
   // Fondo
   ObjectCreate(0, "EA_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "EA_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "EA_BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "EA_BG", OBJPROP_XSIZE, 330);
   ObjectSetInteger(0, "EA_BG", OBJPROP_YSIZE, 210);
   ObjectSetInteger(0, "EA_BG", OBJPROP_BGCOLOR, (color)0x231B16);
   ObjectSetInteger(0, "EA_BG", OBJPROP_BORDER_COLOR, (color)0x4F3B2B);
   ObjectSetInteger(0, "EA_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   // Titulo
   ObjectCreate(0, "EA_TITLE", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "EA_TITLE", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, "EA_TITLE", OBJPROP_YDISTANCE, y + 15);
   ObjectSetString(0, "EA_TITLE", OBJPROP_TEXT, "TELEGRAM TO MT5 PIPELINE");
   ObjectSetInteger(0, "EA_TITLE", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "EA_TITLE", OBJPROP_FONTSIZE, 10);
   
   // Estado Telegram Bot
   string tgStatus = InpEnableTelegram ? (InpTelegramBotToken != "" ? "🟢 Telegram.mqh Activo" : "🟡 Ingrese Bot Token") : "⚪ Telegram Desactivado";
   ObjectCreate(0, "EA_TG_LBL", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "EA_TG_LBL", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, "EA_TG_LBL", OBJPROP_YDISTANCE, y + 40);
   ObjectSetString(0, "EA_TG_LBL", OBJPROP_TEXT, tgStatus);
   ObjectSetInteger(0, "EA_TG_LBL", OBJPROP_COLOR, clrLightSkyBlue);
   ObjectSetInteger(0, "EA_TG_LBL", OBJPROP_FONTSIZE, 9);
   
   // Estado Servidores
   ObjectCreate(0, "EA_SRV_LBL", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "EA_SRV_LBL", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, "EA_SRV_LBL", OBJPROP_YDISTANCE, y + 62);
   ObjectSetString(0, "EA_SRV_LBL", OBJPROP_TEXT, "n8n :5678  |  PocketBase :8090");
   ObjectSetInteger(0, "EA_SRV_LBL", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, "EA_SRV_LBL", OBJPROP_FONTSIZE, 8);
   
   // Estado en tiempo real
   ObjectCreate(0, "EA_STATUS_MSG", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "EA_STATUS_MSG", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, "EA_STATUS_MSG", OBJPROP_YDISTANCE, y + 84);
   ObjectSetString(0, "EA_STATUS_MSG", OBJPROP_TEXT, "Estado: En espera de señales...");
   ObjectSetInteger(0, "EA_STATUS_MSG", OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, "EA_STATUS_MSG", OBJPROP_FONTSIZE, 8);
   
   // Boton Test BUY GOLD
   ObjectCreate(0, "BTN_BUY_GOLD", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "BTN_BUY_GOLD", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, "BTN_BUY_GOLD", OBJPROP_YDISTANCE, y + 115);
   ObjectSetInteger(0, "BTN_BUY_GOLD", OBJPROP_XSIZE, 140);
   ObjectSetInteger(0, "BTN_BUY_GOLD", OBJPROP_YSIZE, 35);
   ObjectSetString(0, "BTN_BUY_GOLD", OBJPROP_TEXT, "⚡ TEST BUY GOLD");
   ObjectSetInteger(0, "BTN_BUY_GOLD", OBJPROP_BGCOLOR, (color)0x2E8B57);
   ObjectSetInteger(0, "BTN_BUY_GOLD", OBJPROP_COLOR, clrWhite);
   
   // Boton Test SELL EURUSD
   ObjectCreate(0, "BTN_SELL_EUR", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "BTN_SELL_EUR", OBJPROP_XDISTANCE, x + 175);
   ObjectSetInteger(0, "BTN_SELL_EUR", OBJPROP_YDISTANCE, y + 115);
   ObjectSetInteger(0, "BTN_SELL_EUR", OBJPROP_XSIZE, 140);
   ObjectSetInteger(0, "BTN_SELL_EUR", OBJPROP_YSIZE, 35);
   ObjectSetString(0, "BTN_SELL_EUR", OBJPROP_TEXT, "⚡ TEST SELL EURUSD");
   ObjectSetInteger(0, "BTN_SELL_EUR", OBJPROP_BGCOLOR, (color)0x2222B2);
   ObjectSetInteger(0, "BTN_SELL_EUR", OBJPROP_COLOR, clrWhite);
   
   // Boton Test Conectividad
   ObjectCreate(0, "BTN_CHECK_CONN", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "BTN_CHECK_CONN", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, "BTN_CHECK_CONN", OBJPROP_YDISTANCE, y + 160);
   ObjectSetInteger(0, "BTN_CHECK_CONN", OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, "BTN_CHECK_CONN", OBJPROP_YSIZE, 28);
   ObjectSetString(0, "BTN_CHECK_CONN", OBJPROP_TEXT, "🔍 Test Conectividad Pipeline");
   ObjectSetInteger(0, "BTN_CHECK_CONN", OBJPROP_BGCOLOR, (color)0x5A4632);
   ObjectSetInteger(0, "BTN_CHECK_CONN", OBJPROP_COLOR, clrWhite);
   
   ChartRedraw();
}

void UpdateDashboardStatus(string text)
{
   if(!InpShowDashboard) return;
   ObjectSetString(0, "EA_STATUS_MSG", OBJPROP_TEXT, "Estado: " + text);
   ChartRedraw();
}

void RemoveDashboard()
{
   ObjectDelete(0, "EA_BG");
   ObjectDelete(0, "EA_TITLE");
   ObjectDelete(0, "EA_TG_LBL");
   ObjectDelete(0, "EA_SRV_LBL");
   ObjectDelete(0, "EA_STATUS_MSG");
   ObjectDelete(0, "BTN_BUY_GOLD");
   ObjectDelete(0, "BTN_SELL_EUR");
   ObjectDelete(0, "BTN_CHECK_CONN");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| INICIALIZACION DEL BOT DE TELEGRAM                               |
//+------------------------------------------------------------------+
bool InitializeTelegramBot()
{
   if(!InpEnableTelegram || InpTelegramBotToken == "")
   {
      Print("[TELEGRAM] Modo Telegram desactivado o token vacio. Se pueden usar los botones de prueba.");
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

   PrintFormat("[TELEGRAM CONECTADO] Bot: @%s", g_bot.Name());
   return true;
}

//+------------------------------------------------------------------+
//| EVENTOS MQL5: OnInit, OnDeinit, OnTimer, OnChartEvent            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================================");
   Print("   Iniciando Telegram To MT5 Signal Execution EA        ");
   Print("========================================================");
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   
   InitializeTelegramBot();
   
   if(!EventSetTimer(InpUpdateIntervalSec))
   {
      Print("[ERROR] Fallo al iniciar timer.");
      return INIT_FAILED;
   }
   
   CreateDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   
   if(g_bot != NULL)
   {
      delete g_bot;
      g_bot = NULL;
   }
   
   RemoveDashboard();
   Print("[EXPERT ADVISOR] EA detenido. Motivo: ", reason);
}

void OnTimer()
{
   // 1. Sondeo de nuevos mensajes en Telegram mediante Telegram.mqh
   if(g_bot != NULL)
   {
      int res = g_bot.GetUpdates();
      if(res == 0)
      {
         g_bot.ProcessMessages();
      }
   }
   
   // 2. Monitoreo de posiciones cerradas para registrar en PocketBase
   if(InpReportToPocketBase)
   {
      CheckClosedPositions();
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "BTN_BUY_GOLD")
      {
         Print("[TEST MANUAL] Click en Test BUY GOLD");
         string sym = ResolveSymbol("XAUUSD");
         if(sym == "") sym = "XAUUSD";
         SymbolSelect(sym, true);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         if(ask <= 0) ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         if(dig <= 0) dig = 2;
         
         double entry = ask;
         double sl = NormalizeDouble(entry - 15.0, dig);
         double tp = NormalizeDouble(entry + 15.0, dig);
         
         string testSig = StringFormat("BUY GOLD %.*f SL %.*f TP %.*f", dig, entry, dig, sl, dig, tp);
         PrintFormat("[TEST MANUAL] Señal generada con precio en vivo: '%s'", testSig);
         UpdateDashboardStatus("Enviando Test BUY GOLD...");
         ProcessPipelineSignal(testSig, "MANUAL_TEST_UI", IntegerToString(TimeCurrent()));
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_SELL_EUR")
      {
         Print("[TEST MANUAL] Click en Test SELL EURUSD");
         string sym = ResolveSymbol("EURUSD");
         if(sym == "") sym = "EURUSD";
         SymbolSelect(sym, true);
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         if(bid <= 0) bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         if(dig <= 0) dig = 5;
         
         double entry = bid;
         double sl = NormalizeDouble(entry + 0.0030, dig);
         double tp = NormalizeDouble(entry - 0.0030, dig);
         
         string testSig = StringFormat("SELL EURUSD %.*f SL %.*f TP %.*f", dig, entry, dig, sl, dig, tp);
         PrintFormat("[TEST MANUAL] Señal generada con precio en vivo: '%s'", testSig);
         UpdateDashboardStatus("Enviando Test SELL EURUSD...");
         ProcessPipelineSignal(testSig, "MANUAL_TEST_UI", IntegerToString(TimeCurrent()));
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_CHECK_CONN")
      {
         Print("[TEST MANUAL] Verificando conectividad...");
         string resp, hdrs;
         int statusPB = HttpGet(InpPocketBaseUrl + "/api/health", resp, hdrs);
         PrintFormat("[CONEXION] PocketBase: %s (Status %d)", (statusPB == 200 ? "OK" : "FALLO"), statusPB);
         
         string pingN8n = "{\"message\":\"PING_TEST\",\"channel_id\":\"0\",\"telegram_msg_id\":\"0\"}";
         int statusN8n = HttpPost(InpN8nWebhookUrl, pingN8n, resp, hdrs);
         PrintFormat("[CONEXION] n8n Webhook: %s (Status %d)", (statusN8n == 200 ? "OK" : "FALLO"), statusN8n);
         
         UpdateDashboardStatus(StringFormat("PB: %s | n8n: %s", (statusPB == 200 ? "OK" : "FAIL"), (statusN8n == 200 ? "OK" : "FAIL")));
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
