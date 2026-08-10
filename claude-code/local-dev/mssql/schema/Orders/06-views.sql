/*
    Orders - views.
*/

CREATE OR ALTER VIEW dbo.vw_OpenOrder
AS
SELECT
    o.OrderId,
    o.ClOrdId,
    o.AccountId,
    a.AccountCode,
    o.InstrumentId,
    i.Symbol,
    i.CurrencyCode,
    o.SideCode,
    o.OrderTypeCode,
    o.TifCode,
    o.StatusCode,
    o.OrderQty,
    o.LimitPrice,
    o.LeavesQty,
    o.CumQty,
    o.AvgPx,
    o.Venue,
    o.CreatedAtUtc,
    o.UpdatedAtUtc
FROM dbo.[Order] AS o
INNER JOIN ReferenceData.dbo.Instrument AS i
    ON i.InstrumentId = o.InstrumentId
INNER JOIN Trading.dbo.Account AS a
    ON a.AccountId = o.AccountId
WHERE o.LeavesQty > 0;
GO

CREATE OR ALTER VIEW dbo.vw_ExecutionEnriched
AS
SELECT
    x.ExecutionId,
    x.ExecId,
    x.OrderId,
    o.ClOrdId,
    o.AccountId,
    a.AccountCode,
    o.InstrumentId,
    i.Symbol,
    i.CurrencyCode,
    o.SideCode,
    x.LastQty,
    x.LastPx,
    GrossValue = CAST(x.LastQty * x.LastPx AS DECIMAL(19, 4)),
    x.Commission,
    NetValue   = CAST(x.LastQty * x.LastPx AS DECIMAL(19, 4))
                 + CASE WHEN o.SideCode = 'BUY' THEN x.Commission ELSE -x.Commission END,
    x.TradeDate,
    x.SettlementDate,
    x.LiquidityFlag,
    x.VenueExecId,
    x.CreatedAtUtc
FROM dbo.Execution AS x
INNER JOIN dbo.[Order] AS o
    ON o.OrderId = x.OrderId
INNER JOIN ReferenceData.dbo.Instrument AS i
    ON i.InstrumentId = o.InstrumentId
INNER JOIN Trading.dbo.Account AS a
    ON a.AccountId = o.AccountId;
GO

CREATE OR ALTER VIEW dbo.vw_OrderFillSummary
AS
SELECT
    o.OrderId,
    o.ClOrdId,
    o.AccountId,
    o.InstrumentId,
    o.SideCode,
    o.StatusCode,
    o.OrderQty,
    o.CumQty,
    o.LeavesQty,
    o.AvgPx,
    FillCount    = COUNT(x.ExecutionId),
    LastFillAtUtc = MAX(x.CreatedAtUtc),
    TotalCommission = ISNULL(SUM(x.Commission), 0),
    FillRatioPct = CASE WHEN o.OrderQty = 0 THEN NULL
                        ELSE CAST(100.0 * o.CumQty / o.OrderQty AS DECIMAL(9, 2)) END
FROM dbo.[Order] AS o
LEFT JOIN dbo.Execution AS x
    ON x.OrderId = o.OrderId
GROUP BY
    o.OrderId,
    o.ClOrdId,
    o.AccountId,
    o.InstrumentId,
    o.SideCode,
    o.StatusCode,
    o.OrderQty,
    o.CumQty,
    o.LeavesQty,
    o.AvgPx;
GO
