#property link          "https://www.earnforex.com/metatrader-expert-advisors/move-stop-breakeven/"
#property version       "1.05"

#property copyright     "EarnForex.com - 2019-2026"
#property description   "This expert advisor will move the stop-loss to breakeven when the price reach a distance from the open price."
#property description   "Optional partial close and BE line display."
#property description   ""
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of this EA cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find More on EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

// 1.041 - Added 'delete Trade;' to DeInit().

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
input bool AdjustForSwapsCommission = false;      // Adjust for swaps & commission?
input double PartialClosePercentage = 0;          // Partial close % (0 = disabled, 1-99)
input string Comment_2 = "====================";  // Orders Filtering Options
input bool OnlyCurrentSymbol = true;              // Apply to current symbol only
input ENUM_CONSIDER OnlyType = All;               // Apply to
input bool UseMagic = false;                      // Filter by magic number
input int MagicNumber = 0;                        // Magic number (if above is true)
input bool UseComment = false;                    // Filter by comment
input string CommentFilter = "";                  // Comment (if above is true)
input bool EnableTrailingParam = false;           // Enable Breakeven EA
input string Comment_3 = "====================";  // BE Trigger Line Display
input bool ShowBELines = false;                   // Show BE trigger price lines
input color BELineColor = clrGold;                // BE line color
input ENUM_LINE_STYLE BELineStyle = STYLE_DASH;   // BE line style
input int BELineWidth = 1;                        // BE line width (1-5)
input int BELabelFontSize = 8;                    // BE label font size
input string Comment_4 = "====================";  // Notification Options
input bool EnableNotify = false;                  // Enable notifications feature
input bool SendAlert = false;                     // Send alert notifications
input bool SendApp = false;                       // Send notifications to mobile
input bool SendEmail = false;                     // Send notifications via email
input string Comment_5 = "====================";  // Graphical Window
input bool ShowPanel = true;                      // Show graphical panel
input string IndicatorName = "MQLTA-MSBE";        // Indicator name (to name the objects)
input int Xoff = 20;                              // Horizontal spacing for the control panel
input int Yoff = 20;                              // Vertical spacing for the control panel
input ENUM_BASE_CORNER ChartCorner = CORNER_LEFT_UPPER; // Chart Corner
input int FontSize = 10;                          // Font Size

double DPIScale; // Scaling parameter for the panel based on the screen DPI.
int PanelMovY, PanelLabX, PanelLabY, PanelRecX;
bool EnableTrailing = EnableTrailingParam;

CTrade *Trade; // Trading object.

// Prefixes for BE trigger line chart objects.
string BELinePrefix;
string BELabelPrefix;

// Partial close tracking: tickets already partially closed.
// Needed only to prevent re-closing if the subsequent BE modification fails.
bool partialCloseEnabled;
long PCClosedTickets[];
int  PCClosedCount = 0;

int OnInit()
{
    CleanPanel();
    EnableTrailing = EnableTrailingParam;

    DPIScale = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;

    PanelMovY = (int)MathRound(20 * DPIScale);
    PanelLabX = (int)MathRound(150 * DPIScale);
    PanelLabY = PanelMovY;
    PanelRecX = PanelLabX + 4;

    BELinePrefix  = IndicatorName + "-BEL-";
    BELabelPrefix = IndicatorName + "-BET-";

    if (ShowPanel) DrawPanel();
    if (ShowBELines && EnableTrailing) DrawBELines();

    partialCloseEnabled = (PartialClosePercentage > 0 && PartialClosePercentage < 100);

    Trade = new CTrade;
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
    CleanBELines();
    ChartRedraw();
    delete Trade;
}

void OnTick()
{
    if (EnableTrailing) TrailingStop();
    if (ShowPanel) DrawPanel();
    if (ShowBELines && EnableTrailing) DrawBELines();
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
    else if (id == CHARTEVENT_CHART_CHANGE)
    {
        if (ShowBELines && EnableTrailing) DrawBELines();
    }
}

void TrailingStop()
{
    // Remove entries for positions that no longer exist.
    if (partialCloseEnabled) CleanupPCList();

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
            if (SymbolInfoDouble(Instrument, SYMBOL_BID) > OpenPrice + DistanceFromOpen * ePoint) SLBuy = OpenPrice + AdditionalProfit * ePoint;
            else continue;
        }
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (SymbolInfoDouble(Instrument, SYMBOL_ASK) < OpenPrice - DistanceFromOpen * ePoint) SLSell = OpenPrice - AdditionalProfit * ePoint;
            else continue;
        }

        double TickSize = SymbolInfoDouble(Instrument, SYMBOL_TRADE_TICK_SIZE);
        int eDigits = (int)SymbolInfoInteger(Instrument, SYMBOL_DIGITS);
        double SLPrice = PositionGetDouble(POSITION_SL);
        double Spread = SymbolInfoInteger(Instrument, SYMBOL_SPREAD) * ePoint;
        double StopLevel = SymbolInfoInteger(Instrument, SYMBOL_TRADE_STOPS_LEVEL) * ePoint;

        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (AdjustForSwapsCommission) SLBuy += CalculateSwapsCommissionAdjustment();
            if (TickSize > 0)
            {
                SLBuy = NormalizeDouble(MathRound(SLBuy / TickSize) * TickSize, eDigits);
            }
            if (SLBuy < SymbolInfoDouble(Instrument, SYMBOL_BID) - StopLevel)
            {
                NewSL = NormalizeDouble(SLBuy, eDigits);
                if (NewSL - SLPrice > ePoint / 2) // Is NewSL higher than the old SL?
                {
                    long posTicket = PositionGetInteger(POSITION_TICKET);
                    if (partialCloseEnabled && !IsTicketPartiallyClosed(posTicket))
                    {
                        int pcResult = ExecutePartialClose(posTicket, Instrument, eDigits);
                        if (pcResult == -1) continue; // Failed, retry next tick.
                        // pcResult 0 (skipped) or 1 (closed) - proceed to BE move.
                    }
                    bool result = false;
                    for (int attempt = 0; attempt < 10; attempt++)
                    {
                        result = Trade.PositionModify(posTicket, NewSL, PositionGetDouble(POSITION_TP));
                        if (result) break;
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting breakeven: Buy Position #", posTicket, " attempt ", attempt + 1, "/10, error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, eDigits),
                              ", old SL = ", DoubleToString(SLPrice, eDigits),
                              ", new SL = ", DoubleToString(NewSL, eDigits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                        Sleep(100);
                    }
                    if (result)
                    {
                        Print("Success setting breakeven: Buy Position #", posTicket, ", new stop-loss = ", DoubleToString(NewSL, eDigits));
                        NotifyStopLossUpdate(posTicket, NewSL, Instrument);
                    }
                }
            }
        }
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (AdjustForSwapsCommission) SLSell -= CalculateSwapsCommissionAdjustment();
            if (TickSize > 0)
            {
                SLSell = NormalizeDouble(MathRound(SLSell / TickSize) * TickSize, eDigits);
            }
            if (SLSell > SymbolInfoDouble(Instrument, SYMBOL_ASK) + StopLevel)
            {
                NewSL = NormalizeDouble(SLSell, eDigits);
                if ((SLPrice - NewSL > ePoint / 2) || (SLPrice == 0)) // Double-safe comparison.
                {
                    long posTicket = PositionGetInteger(POSITION_TICKET);
                    if (partialCloseEnabled && !IsTicketPartiallyClosed(posTicket))
                    {
                        int pcResult = ExecutePartialClose(posTicket, Instrument, eDigits);
                        if (pcResult == -1) continue; // Failed, retry next tick.
                    }
                    bool result = false;
                    for (int attempt = 0; attempt < 10; attempt++)
                    {
                        result = Trade.PositionModify(posTicket, NewSL, PositionGetDouble(POSITION_TP));
                        if (result) break;
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting breakeven: Sell Position #", posTicket, " attempt ", attempt + 1, "/10, error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, eDigits),
                              ", old SL = ", DoubleToString(SLPrice, eDigits),
                              ", new SL = ", DoubleToString(NewSL, eDigits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                        Sleep(100);
                    }
                    if (result)
                    {
                        Print("Success setting breakeven: Sell Position #", posTicket, ", new stop-loss = ", DoubleToString(NewSL, eDigits));
                        NotifyStopLossUpdate(posTicket, NewSL, Instrument);
                    }
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

//+------------------------------------------------------------------+
//| Partial Close Helper Functions                                   |
//+------------------------------------------------------------------+

bool IsTicketPartiallyClosed(long ticket)
{
    for (int i = 0; i < PCClosedCount; i++)
    {
        if (PCClosedTickets[i] == ticket) return true;
    }
    return false;
}

void MarkTicketPartiallyClosed(long ticket)
{
    PCClosedCount++;
    ArrayResize(PCClosedTickets, PCClosedCount);
    PCClosedTickets[PCClosedCount - 1] = ticket;
}

// Attempts to partially close a position. Position must already be selected.
// Returns: 1 = closed, 0 = skipped (lot constraints), -1 = failed.
int ExecutePartialClose(long ticket, string instrument, int eDigits)
{
    double totalLots = PositionGetDouble(POSITION_VOLUME);
    double minLot    = SymbolInfoDouble(instrument, SYMBOL_VOLUME_MIN);
    double lotStep   = SymbolInfoDouble(instrument, SYMBOL_VOLUME_STEP);

    double closeLots = MathFloor(totalLots * PartialClosePercentage / 100.0 / lotStep) * lotStep;
    closeLots = NormalizeDouble(closeLots, 8);

    if (closeLots < minLot)
    {
        Print("Partial close skipped for #", ticket, ": calculated lot (", DoubleToString(closeLots, 2),
              ") below minimum (", DoubleToString(minLot, 2), ").");
        MarkTicketPartiallyClosed(ticket);
        return 0;
    }
    if (totalLots - closeLots < minLot)
    {
        Print("Partial close skipped for #", ticket, ": remaining lot would be below minimum.");
        MarkTicketPartiallyClosed(ticket);
        return 0;
    }

    for (int attempt = 0; attempt < 10; attempt++)
    {
        bool result = Trade.PositionClosePartial(ticket, closeLots);
        if (result)
        {
            Print("Partial close successful: Position #", ticket, ", closed ", DoubleToString(closeLots, 2),
                  " lots (", DoubleToString(PartialClosePercentage, 1), "%)");
            MarkTicketPartiallyClosed(ticket);
            return 1;
        }

        int Error = GetLastError();
        string ErrorText = GetLastErrorText(Error);
        Print("Partial close attempt ", attempt + 1, "/10 failed: Position #", ticket,
              ", lots = ", DoubleToString(closeLots, 2),
              ", error = ", Error, " (", ErrorText, ")");
        Sleep(100);
    }
    return -1;
}

// Remove entries for positions that no longer exist.
void CleanupPCList()
{
    for (int i = PCClosedCount - 1; i >= 0; i--)
    {
        bool found = false;
        for (int j = 0; j < PositionsTotal(); j++)
        {
            if (PositionGetSymbol(j) == "") continue;
            if (PositionGetInteger(POSITION_TICKET) == PCClosedTickets[i]) { found = true; break; }
        }
        if (!found)
        {
            if (i < PCClosedCount - 1) PCClosedTickets[i] = PCClosedTickets[PCClosedCount - 1];
            PCClosedCount--;
            ArrayResize(PCClosedTickets, PCClosedCount);
        }
    }
}

string PanelBase = IndicatorName + "-P-BAS";
string PanelLabel = IndicatorName + "-P-LAB";
string PanelEnableDisable = IndicatorName + "-P-ENADIS";

void DrawPanel()
{
    int SignX = 1;
    int YAdjustment = 0;
    if ((ChartCorner == CORNER_RIGHT_UPPER) || (ChartCorner == CORNER_RIGHT_LOWER))
    {
        SignX = -1; // Correction for right-side panel position.
    }
    if ((ChartCorner == CORNER_RIGHT_LOWER) || (ChartCorner == CORNER_LEFT_LOWER))
    {
        YAdjustment = (PanelMovY + 2) * 2 + 1 - PanelLabY; // Correction for upper side panel position.
    }

    string PanelText = "BREAKEVEN";
    string PanelToolTip = "Move stop to breakeven";
    int Rows = 1;
    ObjectCreate(ChartID(), PanelBase, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_CORNER, ChartCorner);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_XDISTANCE, Xoff);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_YDISTANCE, Yoff + YAdjustment);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_YSIZE, (PanelMovY + 1) * (Rows + 1) + 3);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_BGCOLOR, clrWhite);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_HIDDEN, true);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_COLOR, clrBlack);

    DrawEdit(PanelLabel,
             Xoff + 2 * SignX,
             Yoff + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             PanelToolTip,
             ALIGN_CENTER,
             "Consolas",
             PanelText,
             false,
             clrNavy,
             clrKhaki,
             clrBlack);
    ObjectSetInteger(ChartID(), PanelLabel, OBJPROP_CORNER, ChartCorner);

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

    if (ObjectFind(ChartID(), PanelEnableDisable) >= 0)
    {
        ObjectSetString(ChartID(), PanelEnableDisable, OBJPROP_TEXT, EnableDisabledText);
        ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_COLOR, EnableDisabledColor);
        ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_BGCOLOR, EnableDisabledBack);
    }
    else DrawEdit(PanelEnableDisable,
             Xoff + 2 * SignX,
             Yoff + (PanelMovY + 1) * Rows + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             "Click to enable or disable the breakeven feature.",
             ALIGN_CENTER,
             "Consolas",
             EnableDisabledText,
             false,
             EnableDisabledColor,
             EnableDisabledBack,
             clrBlack);
    ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_CORNER, ChartCorner);
    ChartRedraw();
}

void CleanPanel()
{
    ObjectsDeleteAll(ChartID(), IndicatorName + "-P-");
}


//+------------------------------------------------------------------+
//| BE Trigger Line Display Functions                                |
//+------------------------------------------------------------------+

// Check if a position's BE has already been triggered.
bool IsBEAlreadyTriggered(long posType, double openPrice, double currentSL, double ePoint)
{
    if (currentSL == 0) return false;
    if (posType == POSITION_TYPE_BUY)
    {
        double targetSL = openPrice + AdditionalProfit * ePoint;
        if (currentSL >= targetSL - ePoint / 2) return true;
    }
    else if (posType == POSITION_TYPE_SELL)
    {
        double targetSL = openPrice - AdditionalProfit * ePoint;
        if (currentSL <= targetSL + ePoint / 2) return true;
    }
    return false;
}

void DrawBELines()
{
    long activeTickets[];
    int activeCount = 0;

    // Get the time of the leftmost visible bar on the chart.
    int firstVisibleBar = (int)ChartGetInteger(ChartID(), CHART_FIRST_VISIBLE_BAR);
    datetime leftEdgeTime = iTime(Symbol(), Period(), firstVisibleBar);

    for (int i = 0; i < PositionsTotal(); i++)
    {
        string instrument = PositionGetSymbol(i);
        if (instrument == "") continue;

        // Lines are price-based – only meaningful for the chart's own symbol.
        if (instrument != Symbol()) continue;

        // Apply the same filters the EA uses.
        if ((UseMagic) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((UseComment) && (StringFind(PositionGetString(POSITION_COMMENT), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (PositionGetInteger(POSITION_TYPE) != OnlyType)) continue;

        long   ticket    = PositionGetInteger(POSITION_TICKET);
        long   posType   = PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double ePoint    = SymbolInfoDouble(instrument, SYMBOL_POINT);
        int    eDigits   = (int)SymbolInfoInteger(instrument, SYMBOL_DIGITS);

        // If BE has already been triggered for this position, remove its line and skip.
        if (IsBEAlreadyTriggered(posType, openPrice, PositionGetDouble(POSITION_SL), ePoint))
        {
            DeleteBELineForTicket(ticket);
            continue;
        }

        // Calculate the BE trigger price level.
        double triggerPrice = 0;
        if (posType == POSITION_TYPE_BUY)
            triggerPrice = openPrice + DistanceFromOpen * ePoint;
        else if (posType == POSITION_TYPE_SELL)
            triggerPrice = openPrice - DistanceFromOpen * ePoint;

        triggerPrice = NormalizeDouble(triggerPrice, eDigits);

        activeCount++;
        ArrayResize(activeTickets, activeCount);
        activeTickets[activeCount - 1] = ticket;

        // Draw or update the horizontal line.
        string lineName  = BELinePrefix  + IntegerToString(ticket);
        string labelName = BELabelPrefix + IntegerToString(ticket);

        ObjectCreate(ChartID(), lineName, OBJ_HLINE, 0, 0, triggerPrice);
        ObjectSetDouble(ChartID(), lineName, OBJPROP_PRICE, triggerPrice);
        ObjectSetInteger(ChartID(), lineName, OBJPROP_COLOR, BELineColor);
        ObjectSetInteger(ChartID(), lineName, OBJPROP_STYLE, BELineStyle);
        ObjectSetInteger(ChartID(), lineName, OBJPROP_WIDTH, BELineWidth);
        ObjectSetInteger(ChartID(), lineName, OBJPROP_BACK, true);
        ObjectSetInteger(ChartID(), lineName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(ChartID(), lineName, OBJPROP_HIDDEN, true);
        ObjectSetString(ChartID(), lineName, OBJPROP_TOOLTIP, "BE trigger for #" + IntegerToString(ticket));

        // Text label near the line.
        string typeStr = (posType == POSITION_TYPE_BUY) ? "Buy" : "Sell";
        string labelText = "BE #" + IntegerToString(ticket) + " " + typeStr;

        ObjectCreate(ChartID(), labelName, OBJ_TEXT, 0, leftEdgeTime, triggerPrice);
        ObjectSetDouble(ChartID(), labelName, OBJPROP_PRICE, triggerPrice);
        ObjectSetInteger(ChartID(), labelName, OBJPROP_TIME, leftEdgeTime);
        ObjectSetString(ChartID(), labelName, OBJPROP_TEXT, labelText);
        ObjectSetInteger(ChartID(), labelName, OBJPROP_COLOR, BELineColor);
        ObjectSetInteger(ChartID(), labelName, OBJPROP_FONTSIZE, BELabelFontSize);
        ObjectSetString(ChartID(), labelName, OBJPROP_FONT, "Arial");
        ObjectSetInteger(ChartID(), labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
        ObjectSetInteger(ChartID(), labelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(ChartID(), labelName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(ChartID(), labelName, OBJPROP_BACK, false);
    }

    PurgeStaleBELines(activeTickets, activeCount);
    ChartRedraw();
}

void DeleteBELineForTicket(long ticket)
{
    string lineName  = BELinePrefix  + IntegerToString(ticket);
    string labelName = BELabelPrefix + IntegerToString(ticket);
    ObjectDelete(ChartID(), lineName);
    ObjectDelete(ChartID(), labelName);
}

void PurgeStaleBELines(long &activeTickets[], int activeCount)
{
    int totalObjects = ObjectsTotal(ChartID());
    for (int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(ChartID(), i);
        bool isLine  = (StringFind(objName, BELinePrefix)  == 0);
        bool isLabel = (StringFind(objName, BELabelPrefix) == 0);
        if (!isLine && !isLabel) continue;

        string prefix = isLine ? BELinePrefix : BELabelPrefix;
        string ticketStr = StringSubstr(objName, StringLen(prefix));
        long ticket = StringToInteger(ticketStr);

        bool found = false;
        for (int k = 0; k < activeCount; k++)
        {
            if (activeTickets[k] == ticket) { found = true; break; }
        }
        if (!found) ObjectDelete(ChartID(), objName);
    }
}

void CleanBELines()
{
    ObjectsDeleteAll(ChartID(), BELinePrefix);
    ObjectsDeleteAll(ChartID(), BELabelPrefix);
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            MessageBox("Algorithmic trading is disabled in the platform's options! Please enable it via Tools->Options->Expert Advisors.", "WARNING", MB_OK);
            return;
        }
        if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
            MessageBox("Algo Trading is disabled in the advsior's settings! Please tick the Allow Algo Trading checkbox on the Common tab.", "WARNING", MB_OK);
            return;
        }
        EnableTrailing = true;
        if (ShowBELines) DrawBELines();
    }
    else
    {
        EnableTrailing = false;
        if (ShowBELines) CleanBELines();
    }
    DrawPanel();
}

enum mode_of_operation
{
    Risk,
    Reward
};

string AccCurrency;
double CalculateSwapsCommissionAdjustment()
{
    // Commission is usually a negative value.
    // Swaps can be positive and negative. A positive swap means that we got extra money.
    // When the minus sign below gets applied to a negative value (incurred commission/swap losses), it makes a positive value in currency to compensate by moving the SL favorably from the breakeven point.
    double money = -(CalculateCommission() + PositionGetDouble(POSITION_SWAP));

    if (money == 0) return 0; // Nothing to compensate.
    AccCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    mode_of_operation mode = Risk;
    if (money < 0) mode = Reward;
    double point_value = CalculatePointValue(mode);

    if (point_value != 0) return money / point_value;
    else return 0; // Zero point value. Avoiding division by zero.
}

double CalculatePointValue(mode_of_operation mode)
{
    string cp = PositionGetString(POSITION_SYMBOL);
    double UnitCost = CalculateUnitCost(cp, mode);
    double OnePoint = SymbolInfoDouble(cp, SYMBOL_POINT);
    return(UnitCost / OnePoint);
}

//+----------------------------------------------------------------------+
//| Returns unit cost either for Risk or for Reward mode.                |
//+----------------------------------------------------------------------+
double CalculateUnitCost(const string cp, const mode_of_operation mode)
{
    ENUM_SYMBOL_CALC_MODE CalcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(cp, SYMBOL_TRADE_CALC_MODE);

    // No-Forex.
    if ((CalcMode != SYMBOL_CALC_MODE_FOREX) && (CalcMode != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) && (CalcMode != SYMBOL_CALC_MODE_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS))
    {
        double TickSize = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE);
        double UnitCost = TickSize * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE);
        string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
        if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";

        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            return(UnitCost * CalculateAdjustment(ProfitCurrency, mode));
        }
        return UnitCost;
    }
    // With Forex instruments, tick value already equals 1 unit cost.
    else
    {
        if (mode == Risk) return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_LOSS);
        else return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_PROFIT);
    }
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when GivenCurrency != AccountCurrency. |
//| Used in two cases: profit adjustment and margin adjustment.                       |
//+-----------------------------------------------------------------------------------+
double CalculateAdjustment(const string ProfitCurrency, const mode_of_operation mode)
{
    string ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, AccCurrency);
    bool ReferenceSymbolMode = true;
    // Failed.
    if (ReferenceSymbol == NULL)
    {
        // Reversing currencies.
        ReferenceSymbol = GetSymbolByCurrencies(AccCurrency, ProfitCurrency);
        ReferenceSymbolMode = false;
    }
    // Everything failed.
    if (ReferenceSymbol == NULL)
    {
        Print("Error! Cannot detect proper currency pair for adjustment calculation: ", ProfitCurrency, ", ", AccCurrency, ".");
        ReferenceSymbol = Symbol();
        return 1;
    }
    MqlTick tick;
    SymbolInfoTick(ReferenceSymbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, mode, ReferenceSymbolMode);
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(string base_currency, string profit_currency)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);

        // Skip non-Forex pairs.
        if ((SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX) && (SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)) continue;

        // Get its base currency.
        string b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        if (b_cur == "RUR") b_cur = "RUB";

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);
        if (p_cur == "RUR") p_cur = "RUB";
        
        // If the currency pair matches both currencies, select it in Market Watch and return its name.
        if ((b_cur == base_currency) && (p_cur == profit_currency))
        {
            // Select if necessary.
            if (!(bool)SymbolInfoInteger(symbolname, SYMBOL_SELECT)) SymbolSelect(symbolname, true);

            return symbolname;
        }
    }
    return NULL;
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on profit currency,      |
//| calculation mode (profit or loss), reference pair mode (reverse  |
//| or direct), and current prices.                                  |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick, const mode_of_operation mode, const bool ReferenceSymbolMode)
{
    if ((tick.ask == 0) || (tick.bid == 0)) return -1; // Data is not yet ready.
    if (mode == Risk)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Buy price for reverse quote.
            return tick.ask;
        }
        // Direct quote.
        else
        {
            // Using Sell price for direct quote.
            return(1 / tick.bid);
        }
    }
    else if (mode == Reward)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Sell price for reverse quote.
            return tick.bid;
        }
        // Direct quote.
        else
        {
            // Using Buy price for direct quote.
            return(1 / tick.ask);
        }
    }
    return -1;
}

double CalculateCommission()
{
    double commission_sum = 0;
    if (!HistorySelectByPosition(PositionGetInteger(POSITION_IDENTIFIER)))
    {
        Print("HistorySelectByPosition failed: ", GetLastError());
        return 0;
    }
    int deals_total = HistoryDealsTotal();
    for (int i = 0; i < deals_total; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if (deal_ticket == 0)
        {
            Print("HistoryDealGetTicket failed: ", GetLastError());
            continue;
        }
        if ((HistoryDealGetInteger(deal_ticket, DEAL_TYPE) != DEAL_TYPE_BUY) && (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) != DEAL_TYPE_SELL)) continue; // Wrong kinds of deals.
        if (HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue; // Only entry deals.
        commission_sum += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
    }
    return commission_sum;
}
//+------------------------------------------------------------------+