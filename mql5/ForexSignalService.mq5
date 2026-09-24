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
//| PARAMETROS DE CONFIGURACION DEL SERVICIO                         |
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
input bool     InpNotifyTelegramReply = false;                                  // Responder al chat de Telegram con confirmacion

input group "=== RISK & EXECUTION SETTINGS ===";
input ulong    InpMagicNumber         = 888999;             // Magic Number
input double   InpDefaultLot          = 0.01;               // Lotaje por defecto si la senal no define
input ulong    InpSlippagePoints      = 30;                 // Desviacion / Slippage maximo en puntos
input string   InpSymbolSuffix        = "";                 // Sufijo del broker (ej: .m, m, .pro) vacio=auto

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
            if(g_tracked_trades[i].action == "BUY" || g_tracked_trades[i].action == "LONG")
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
//| EJECUCION DE ORDEN EN CUALQUIER SIMBOLO                          |
//+------------------------------------------------------------------+
bool ExecuteTrade(string symbol, string action, double lot, double entry, double sl, double tp, string channelId, string msgId, string orderComment="")
{
   string brokerSymbol = ResolveSymbol(symbol);
   if(brokerSymbol == "")
   {
      PrintFormat("[TRADE ERROR] Simbolo '%s' no existe en el broker.", symbol);
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
   bool isBuy = (action == "BUY" || action == "LONG");
   bool isSell = (action == "SELL" || action == "SHORT");

   if(!isBuy && !isSell)
   {
      PrintFormat("[TRADE ERROR] Accion desconocida: %s. Solo se admiten BUY, LONG, SELL, SHORT.", action);
      return false;
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
   
   PrintFormat("[SERVICE APROBADA] Orden verificada: %s %s Lot=%.2f Entry=%.5f SL=%.5f TP=%.5f Canal=%s Comentario=%s",
               action, symbol, lot, entry, sl, tp, channelId, comment);
               
   ExecuteTrade(symbol, action, lot, entry, sl, tp, channelId, msgId, comment);
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
      
      // 2. Monitoreo de posiciones cerradas para PocketBase
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
