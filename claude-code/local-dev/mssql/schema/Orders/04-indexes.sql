/*
    Orders - indexes.

    The filtered index on working orders is the one the blotter relies on; without it
    local plans diverge sharply from the enterprise instance once seed volume grows.
*/

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Order_Account_Status' AND object_id = OBJECT_ID(N'dbo.[Order]'))
    CREATE NONCLUSTERED INDEX IX_Order_Account_Status
        ON dbo.[Order] (AccountId, StatusCode)
        INCLUDE (InstrumentId, SideCode, OrderQty, LeavesQty, CumQty, AvgPx);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Order_Instrument_CreatedAt' AND object_id = OBJECT_ID(N'dbo.[Order]'))
    CREATE NONCLUSTERED INDEX IX_Order_Instrument_CreatedAt
        ON dbo.[Order] (InstrumentId, CreatedAtUtc DESC)
        INCLUDE (AccountId, SideCode, StatusCode, OrderQty);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Order_Working' AND object_id = OBJECT_ID(N'dbo.[Order]'))
    CREATE NONCLUSTERED INDEX IX_Order_Working
        ON dbo.[Order] (AccountId, InstrumentId)
        INCLUDE (ClOrdId, SideCode, LimitPrice, LeavesQty)
        WHERE LeavesQty > 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Execution_Order' AND object_id = OBJECT_ID(N'dbo.Execution'))
    CREATE NONCLUSTERED INDEX IX_Execution_Order
        ON dbo.Execution (OrderId)
        INCLUDE (LastQty, LastPx, TradeDate);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Execution_TradeDate' AND object_id = OBJECT_ID(N'dbo.Execution'))
    CREATE NONCLUSTERED INDEX IX_Execution_TradeDate
        ON dbo.Execution (TradeDate DESC, OrderId)
        INCLUDE (LastQty, LastPx, Commission);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrderEvent_Order' AND object_id = OBJECT_ID(N'audit.OrderEvent'))
    CREATE NONCLUSTERED INDEX IX_OrderEvent_Order
        ON audit.OrderEvent (OrderId, EventAtUtc DESC);
GO
