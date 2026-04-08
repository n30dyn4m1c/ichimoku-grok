//+------------------------------------------------------------------+
//| Ichimoku Multi-Tier Alignment EA (MN?M1, H4?M1, H1?M1)         |
//| Trades three conviction tiers with tier-specific exits           |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols   = "GOLD,XAUUSD,SILVER,XAGUSD";
input int    Tenkan    = 9;
input int    Kijun     = 26;
input int    SenkouB   = 52;
input double RiskFullPct = 2.0;   // % Risk for Full MN-M1 (Total)
input double RiskH4Pct   = 1.0;   // % Risk for H4-M1 (Total)
input double RiskH1Pct   = 0.5;   // % Risk for H1-M1 (Total)
input int    RiskRefSL   = 1000;  // Reference SL in Points (100 pips)
input int    ATRPeriod   = 14;    // ATR Period for hard SL
input double RiskATRMult = 3.0;   // ATR Multiplier for hard SL (Safety Net)
input int    Slippage    = 30;    // Max slippage in points

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define TF_COUNT 9
#define TIER_COUNT 3

ENUM_TIMEFRAMES TFs[TF_COUNT] = {
   PERIOD_MN1, PERIOD_W1, PERIOD_D1,
   PERIOD_H4, PERIOD_H1, PERIOD_M30,
   PERIOD_M15, PERIOD_M5, PERIOD_M1
};

// Exit TF index per tier: Full=M15(6), H4=M5(7), H1=M1(8)
int ExitTFIndex[TIER_COUNT] = {6, 7, 8};

// Positions per tier: Full=3, H4=3, H1=1
int PositionsPerTier[TIER_COUNT] = {3, 3, 1};

// Magic numbers per tier
int MAGIC_FULL = 20260301;
int MAGIC_H4   = 20260302;
int MAGIC_H1   = 20260303;

int      ich[MAX_SYMS][TF_COUNT];
int      atrM15[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar = 0;

// Track active state per symbol per tier
// 0=no position, 1=long, -1=short
int      tierState[MAX_SYMS][TIER_COUNT];

CTrade   trade;

//==============================================================
// Initialization and Deinitialization
//==============================================================

int ParseSymbols(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   int cnt = 0;

   for(int i = 0; i < n && cnt < MAX_SYMS; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(SymbolSelect(sym, true)) syms[cnt++] = sym;
   }
   return cnt;
}

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      for(int tier = 0; tier < TIER_COUNT; tier++)
         tierState[s][tier] = 0;

      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], TFs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atrM15[s] = iATR(syms[s], PERIOD_M15, ATRPeriod);
      if(atrM15[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   // Set slippage for order execution
   trade.SetDeviationInPoints(Slippage);

   // Scan for existing positions on startup
   SyncStateFromPositions();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
         IndicatorRelease(ich[s][t]);
      IndicatorRelease(atrM15[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;

      int tier = -1;
      if(magic == MAGIC_FULL) tier = 0;
      else if(magic == MAGIC_H4) tier = 1;
      else if(magic == MAGIC_H1) tier = 2;
      else continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym)
         {
            tierState[s][tier] = dir;
            break;
         }
      }
   }
}

//==============================================================
// Ichimoku Rule Check
//==============================================================

int CheckTF(string sym, ENUM_TIMEFRAMES tf, int h)
{
   MqlRates rt[];
   if(CopyRates(sym, tf, 0, 120, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int sh         = 1;
   int priceCloud = sh + 26;
   int chShift    = sh + 26;
   int chCloud    = sh + 52;

   if(ArraySize(rt) <= chCloud) return 0;

   double ten[1], kij[1], senA[1], senB[1], chik[1];
   double ten_ch[1], kij_ch[1], senA_ch[1], senB_ch[1];

   if(CopyBuffer(h, 0, sh, 1, ten) <= 0) return 0;
   if(CopyBuffer(h, 1, sh, 1, kij) <= 0) return 0;
   if(CopyBuffer(h, 2, priceCloud, 1, senA) <= 0) return 0;
   if(CopyBuffer(h, 3, priceCloud, 1, senB) <= 0) return 0;

   if(CopyBuffer(h, 4, chShift, 1, chik) <= 0) return 0;
   if(CopyBuffer(h, 0, chShift, 1, ten_ch) <= 0) return 0;
   if(CopyBuffer(h, 1, chShift, 1, kij_ch) <= 0) return 0;
   if(CopyBuffer(h, 2, chCloud, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(h, 3, chCloud, 1, senB_ch) <= 0) return 0;

   double closeP   = rt[sh].close;
   double price_26 = rt[chShift].close;

   double cHi  = MathMax(senA[0], senB[0]);
   double cLo  = MathMin(senA[0], senB[0]);
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   bool priceAbove = (closeP > cHi && closeP > ten[0] && closeP > kij[0]);
   bool priceBelow = (closeP < cLo && closeP < ten[0] && closeP < kij[0]);

   bool chAbove = (chik[0] > cHiC && chik[0] > ten_ch[0] && chik[0] > kij_ch[0] && chik[0] > price_26);
   bool chBelow = (chik[0] < cLoC && chik[0] < ten_ch[0] && chik[0] < kij_ch[0] && chik[0] < price_26);

   if(priceAbove && chAbove) return 1;
   if(priceBelow && chBelow) return -1;

   return 0;
}

//==============================================================
// Alignment Check Functions
//==============================================================

int AlignRange(const int s, const int from, const int to)
{
   int state = 0;
   for(int t = from; t <= to; t++)
   {
      int st = CheckTF(syms[s], TFs[t], ich[s][t]);
      if(st == 0) return 0;
      if(t == from) state = st;
      else if(st != state) return 0;
   }
   return state;
}

// MN ? M1 (indices 0-8, all 9 TFs)
int AlignFull(const int s) { return AlignRange(s, 0, 8); }

// H4 ? M1 (indices 3-8, 6 TFs)
int AlignH4(const int s)   { return AlignRange(s, 3, 8); }

// H1 ? M1 (indices 4-8, 5 TFs)
int AlignH1(const int s)   { return AlignRange(s, 4, 8); }

//==============================================================
// Utility Functions
//==============================================================

string PCTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   int h = dt.hour;
   string ampm = (h >= 12) ? "PM" : "AM";
   if(h == 0) h = 12;
   else if(h > 12) h -= 12;
   return IntegerToString(h) + ":" + StringFormat("%02d", dt.min) + " " + ampm;
}

int GetSymIndex(string sym)
{
   for(int s = 0; s < symsCount; s++)
      if(syms[s] == sym) return s;
   return -1;
}

//==============================================================
// Trading Functions
//==============================================================

int MagicForTier(const int tier)
{
   if(tier == 0) return MAGIC_FULL;
   if(tier == 1) return MAGIC_H4;
   return MAGIC_H1;
}

double NormalizeLot(string sym, double lot)
{
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, lot);
   lot = MathMin(maxLot, lot);
   lot = MathFloor(lot / stepLot) * stepLot;
   int digits = (int)MathRound(-MathLog10(stepLot + 1e-10));
   return NormalizeDouble(lot, digits);
}

double LotsForTier(string sym, const int tier)
{
   double pct = (tier == 0) ? RiskFullPct : (tier == 1 ? RiskH4Pct : RiskH1Pct);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = balance * (pct / 100.0);
   double tickV   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickS   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(tickV <= 0 || tickS <= 0 || RiskRefSL <= 0) return 0.01;

   double sl_in_price = RiskRefSL * point;
   double ticks = sl_in_price / tickS;
   
   // Total lots for this tier
   double totalLots = risk / (ticks * tickV);
   
   // Lots per position (Full/H4 have 3, H1 has 1)
   double lots = totalLots / (double)PositionsPerTier[tier];
   
   return NormalizeLot(sym, lots);
}

string TierLabel(const int tier)
{
   if(tier == 0) return "Full MN-M1";
   if(tier == 1) return "H4-M1";
   return "H1-M1";
}

bool OpenPositions(string sym, bool isBuy, int tier)
{
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double lots  = LotsForTier(sym, tier);
   int    count = PositionsPerTier[tier];

   int s = GetSymIndex(sym);
   double sl = 0;
   if(s >= 0)
   {
      double atr[1];
      if(CopyBuffer(atrM15[s], 0, 1, 1, atr) > 0)
      {
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double slDist = atr[0] * RiskATRMult;
         if(isBuy) sl = NormalizeDouble(ask - slDist, digits);
         else      sl = NormalizeDouble(bid + slDist, digits);
      }
   }

   trade.SetExpertMagicNumber(MagicForTier(tier));

   bool ok = true;
   for(int i = 0; i < count; i++)
   {
      if(isBuy)
      {
         if(!trade.Buy(lots, sym, ask, sl, 0, TierLabel(tier)))
            ok = false;
      }
      else
      {
         if(!trade.Sell(lots, sym, bid, sl, 0, TierLabel(tier)))
            ok = false;
      }
   }
   return ok;
}

void ClosePositions(string sym, int tier)
{
   int magic = MagicForTier(tier);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == magic)
      {
         trade.PositionClose(ticket);
      }
   }
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   MqlRates m1[];
   if(CopyRates(_Symbol, PERIOD_M1, 0, 2, m1) <= 0) return;
   ArraySetAsSeries(m1, true);
   if(m1[1].time == lastM1bar) return;
   lastM1bar = m1[1].time;

   for(int s = 0; s < symsCount; s++)
   {
      // --- Exit checks FIRST (per tier, based on specific TF break) ---

      for(int tier = 0; tier < TIER_COUNT; tier++)
      {
         if(tierState[s][tier] == 0) continue;

         int exitIdx = ExitTFIndex[tier];
         int exitSt  = CheckTF(syms[s], TFs[exitIdx], ich[s][exitIdx]);

         // Exit if the exit TF broke (neutral or flipped)
         if(exitSt != tierState[s][tier])
         {
            string side = (tierState[s][tier] == 1) ? "Long" : "Short";
            string msg = PCTime() + " | Close " + syms[s] + " " + side + " (" + TierLabel(tier) + " - " +
                         EnumToString(TFs[exitIdx]) + " broke)";
            Print(msg); Alert(msg); SendNotification(msg);

            ClosePositions(syms[s], tier);
            tierState[s][tier] = 0;
         }
      }

      // --- Entry checks (exclusive tiers) ---
      // Only enter if no position exists for that tier on this symbol

      // Tier 0: Full MN-M1
      if(tierState[s][0] == 0)
      {
         int st = AlignFull(s);
         if(st != 0)
         {
            bool isBuy = (st == 1);
            string action = isBuy ? "Buy" : "Sell";
            string msg = PCTime() + " | " + action + " " + syms[s] + " x3 @ " + DoubleToString(LotsForTier(syms[s], 0), 2) + " (Full MN-M1)";
            Print(msg); Alert(msg); SendNotification(msg);

            if(OpenPositions(syms[s], isBuy, 0))
               tierState[s][0] = st;
         }
      }

      // Tier 1: H4-M1 (only if Full not active)
      if(tierState[s][1] == 0 && tierState[s][0] == 0)
      {
         int st = AlignH4(s);
         if(st != 0)
         {
            bool isBuy = (st == 1);
            string action = isBuy ? "Buy" : "Sell";
            string msg = PCTime() + " | " + action + " " + syms[s] + " x3 @ " + DoubleToString(LotsForTier(syms[s], 1), 2) + " (H4-M1)";
            Print(msg); Alert(msg); SendNotification(msg);

            if(OpenPositions(syms[s], isBuy, 1))
               tierState[s][1] = st;
         }
      }

      // Tier 2: H1-M1 (only if H4 and Full not active)
      if(tierState[s][2] == 0 && tierState[s][1] == 0 && tierState[s][0] == 0)
      {
         int st = AlignH1(s);
         if(st != 0)
         {
            bool isBuy = (st == 1);
            string action = isBuy ? "Buy" : "Sell";
            string msg = PCTime() + " | " + action + " " + syms[s] + " x1 @ " + DoubleToString(LotsForTier(syms[s], 2), 2) + " (H1-M1)";
            Print(msg); Alert(msg); SendNotification(msg);

            if(OpenPositions(syms[s], isBuy, 2))
               tierState[s][2] = st;
         }
      }
   }
}
