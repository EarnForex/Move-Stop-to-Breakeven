#property link          "https://www.earnforex.com/metatrader-expert-advisors/move-stop-breakeven/"
#property version       "1.03"

#property copyright     "EarnForex.com - 2019-2024"
#property description   "This expert advisor will move the stop-loss to breakeven when the price reach a distance from the open price."
#property description   ""
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of this EA cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find More on EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>
#include <Trade/Trade.mqh>

enum ENUM_CONSIDER
{
    All = -1,                  // ALL ORDERS
    Buy = POSITION_TYPE_BUY,   // BUY ONLY
    Sell = POSITION_TYPE_SELL  // SELL ONLY
};

input string Comment_1 = "====================";  // Expert Advisor Settings
input int DistanceFromOpen = 500;                 // Points of distance from the open price
input int AdditionalProfit = 0;                   // Additional profit in points to add to BE
input string Comment_2 = "====================";  // Orders Filtering Options
input bool OnlyCurrentSymbol = true;              // Apply to current symbol only
input ENUM_CONSIDER OnlyType = All;               // Apply to
input bool UseMagic = false;                      // Filter by magic number
input int MagicNumber = 0;                        // Magic number (if above is true)
input bool UseComment = false;                    // Filter by comment
input string CommentFilter = "";                  // Comment (if above is true)
input bool EnableTrailingParam = false;           // Enable Breakeven EA
input string Comment_3 = "====================";  // Notification Options
input bool EnableNotify = false;                  // Enable notifications feature
input bool SendAlert = false;                     // Send alert notifications
input bool SendApp = false;                       // Send notifications to mobile
input bool SendEmail = false;                     // Send notifications via email
input string Comment_3a = "===================="; // Graphical Window
input bool ShowPanel = true;                      // Show graphical panel
input string IndicatorName = "MQLTA-MSBE";        // Indicator name (to name the objects)
input int Xoff = 20;                              // Horizontal spacing for the control panel
input int Yoff = 20;                              // Vertical spacing for the control panel

bool EnableTrailing = EnableTrailingParam;

CTrade *Trade; // Trading object.

int OnInit()
{
    EnableTrailing = EnableTrailingParam;
    if (ShowPanel) DrawPanel();
    Trade = new CTrade;
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
}

void OnTick()
{
    if (EnableTrailing) TrailingStop();
    if (ShowPanel) DrawPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        if (sparam == PanelEnableDisable)
        {
            ChangeTrailingEnabled();
        }
    }
    else if (id == CHARTEVENT_KEYDOWN)
    {
        if (lparam == 27)
        {
            if (MessageBox("Are you sure you want to close the EA?", "EXIT ?", MB_YESNO) == IDYES)
            {
                ExpertRemove();
            }
        }
    }
}

void TrailingStop()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        string Instrument = PositionGetSymbol(i);
        if (Instrument == "")
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the position - ", Error);
            Print("ERROR - ", ErrorText);
            continue;
        }
        if ((OnlyCurrentSymbol) && (Instrument != Symbol())) continue;
        if ((UseMagic) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((UseComment) && (StringFind(PositionGetString(POSITION_COMMENT), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (PositionGetInteger(POSITION_TYPE) != OnlyType)) continue;

        double NewSL = 0;
        double NewTP = 0;
        double SLBuy = 0;
        double SLSell = 0;
        double ePoint = SymbolInfoDouble(Instrument, SYMBOL_POINT);
        double OpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);

        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (SymbolInfoDouble(Instrument, SYMBOL_ASK) > OpenPrice + DistanceFromOpen * ePoint) SLBuy = OpenPrice + AdditionalProfit * ePoint;
        }
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (SymbolInfoDouble(Instrument, SYMBOL_BID) < OpenPrice - DistanceFromOpen * ePoint) SLSell = OpenPrice - AdditionalProfit * ePoint;
        }

        int eDigits = (int)SymbolInfoInteger(Instrument, SYMBOL_DIGITS);
        double SLPrice = PositionGetDouble(POSITION_SL);
        double Spread = SymbolInfoInteger(Instrument, SYMBOL_SPREAD) * ePoint;
        double StopLevel = SymbolInfoInteger(Instrument, SYMBOL_TRADE_STOPS_LEVEL) * ePoint;

        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) && (SLBuy < SymbolInfoDouble(Instrument, SYMBOL_BID) - StopLevel))
        {
            NewSL = NormalizeDouble(SLBuy, eDigits);
            if (NewSL - SLPrice > ePoint / 2) // Double-safe comparison.
            {
                bool result = Trade.PositionModify(PositionGetInteger(POSITION_TICKET), NewSL, PositionGetDouble(POSITION_TP));
                if (result)
                {
                    Print("Success setting breakeven: Buy Position #", PositionGetInteger(POSITION_TICKET), ", new stop-loss = ", DoubleToString(NewSL, eDigits));
                    NotifyStopLossUpdate(PositionGetInteger(POSITION_TICKET), NewSL, Instrument);
                }
                else
                {
                    int Error = GetLastError();
                    string ErrorText = GetLastErrorText(Error);
                    Print("Error setting breakeven: Buy Position #", PositionGetInteger(POSITION_TICKET), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, eDigits),
                          ", old SL = ", DoubleToString(SLPrice, eDigits),
                          ", new SL = ", DoubleToString(NewSL, eDigits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                }
            }
        }
        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) && (SLSell > SymbolInfoDouble(Instrument, SYMBOL_ASK) + StopLevel))
        {
            NewSL = NormalizeDouble(SLSell, eDigits);
            if ((SLPrice - NewSL > ePoint / 2) || (SLPrice == 0)) // Double-safe comparison.
            {
                bool result = Trade.PositionModify(PositionGetInteger(POSITION_TICKET), NewSL, PositionGetDouble(POSITION_TP));
                if (result)
                {
                    Print("Success setting breakeven: Sell Position #", PositionGetInteger(POSITION_TICKET), ", new stop-loss = ", DoubleToString(NewSL, eDigits));
                    NotifyStopLossUpdate(PositionGetInteger(POSITION_TICKET), NewSL, Instrument);
                }
                else
                {
                    int Error = GetLastError();
                    string ErrorText = GetLastErrorText(Error);
                    Print("Error setting breakeven: Sell Position #", PositionGetInteger(POSITION_TICKET), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, eDigits),
                          ", old SL = ", DoubleToString(SLPrice, eDigits),
                          ", new SL = ", DoubleToString(NewSL, eDigits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                }
            }
        }
    }
}

void NotifyStopLossUpdate(long Ticket, double SLPrice, string Instrument)
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    string EmailSubject = IndicatorName + " " + Instrument + " Notification";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n\r\n" + IndicatorName + " Notification for " + Instrument + "\r\n\r\n";
    EmailBody += "The stop-loss for order #" + IntegerToString(Ticket) + " has been moved to breakeven.";
    string AlertText = "Stop-loss for order #" + IntegerToString(Ticket) + " has been moved to breakeven.";
    string AppText = IndicatorName + " - " + Instrument + ": ";
    AppText += "Stop-loss for order #" + IntegerToString(Ticket) + " was moved to breakeven.";
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
}

string PanelBase = IndicatorName + "-P-BAS";
string PanelLabel = IndicatorName + "-P-LAB";
string PanelEnableDisable = IndicatorName + "-P-ENADIS";

int PanelMovX = 50;
int PanelMovY = 20;
int PanelLabX = 150;
int PanelLabY = PanelMovY;
int PanelRecX = PanelLabX + 4;

void DrawPanel()
{
    string PanelText = "BREAKEVEN";
    string PanelToolTip = "Move stop to breakeven";
    int Rows = 1;
    ObjectCreate(0, PanelBase, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PanelBase, OBJPROP_XDISTANCE, Xoff);
    ObjectSetInteger(0, PanelBase, OBJPROP_YDISTANCE, Yoff);
    ObjectSetInteger(0, PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(0, PanelBase, OBJPROP_YSIZE, (PanelMovY + 1) * (Rows + 1) + 3);
    ObjectSetInteger(0, PanelBase, OBJPROP_BGCOLOR, clrWhite);
    ObjectSetInteger(0, PanelBase, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, PanelBase, OBJPROP_STATE, false);
    ObjectSetInteger(0, PanelBase, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, PanelBase, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, PanelBase, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, PanelBase, OBJPROP_COLOR, clrBlack);

    DrawEdit(PanelLabel,
             Xoff + 2,
             Yoff + 2,
             PanelLabX,
             PanelLabY,
             true,
             10,
             PanelToolTip,
             ALIGN_CENTER,
             "Consolas",
             PanelText,
             false,
             clrNavy,
             clrKhaki,
             clrBlack);

    string EnableDisabledText = "";
    color EnableDisabledColor = clrNavy;
    color EnableDisabledBack = clrKhaki;
    if (EnableTrailing)
    {
        EnableDisabledText = "EXPERT ENABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkGreen;
    }
    else
    {
        EnableDisabledText = "EXPERT DISABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkRed;
    }

    if (ObjectFind(0, PanelEnableDisable) >= 0)
    {
        ObjectSetString(0, PanelEnableDisable, OBJPROP_TEXT, EnableDisabledText);
        ObjectSetInteger(0, PanelEnableDisable, OBJPROP_COLOR, EnableDisabledColor);
        ObjectSetInteger(0, PanelEnableDisable, OBJPROP_BGCOLOR, EnableDisabledBack);
    }
    else DrawEdit(PanelEnableDisable,
             Xoff + 2,
             Yoff + (PanelMovY + 1) * Rows + 2,
             PanelLabX,
             PanelLabY,
             true,
             8,
             "Click to enable or disable the breakeven feature.",
             ALIGN_CENTER,
             "Consolas",
             EnableDisabledText,
             false,
             EnableDisabledColor,
             EnableDisabledBack,
             clrBlack);
}

void CleanPanel()
{
    ObjectsDeleteAll(0, IndicatorName + "-P-");
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) EnableTrailing = true;
        else
        {
            MessageBox("You first need to enable live trading in MetaTrader options", "WARNING", MB_OK);
        }
    }
    else EnableTrailing = false;
    DrawPanel();
    ChartRedraw();
}
//+------------------------------------------------------------------+