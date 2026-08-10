SET NOCOUNT ON;
GO

SELECT 'ReferenceData.Instrument' AS ObjectName, COUNT(*) AS RowCount
FROM ReferenceData.dbo.Instrument;

SELECT 'Trading.Position' AS ObjectName, COUNT(*) AS RowCount
FROM Trading.dbo.Position;

SELECT 'Orders.EquityOrder' AS ObjectName, COUNT(*) AS RowCount
FROM Orders.dbo.EquityOrder;

SELECT 'Orders.ExecutionReport' AS ObjectName, COUNT(*) AS RowCount
FROM Orders.dbo.ExecutionReport;
GO

SELECT TOP (20)
    o.ClientOrderId,
    o.OrderStatusCode,
    i.Symbol,
    o.Side,
    o.OrderQty,
    o.CumQty,
    o.LeavesQty,
    o.LimitPrice
FROM Orders.dbo.vOrderBlotter AS o
JOIN ReferenceData.dbo.Instrument AS i ON i.InstrumentId = o.InstrumentId
ORDER BY o.ClientOrderId;
GO

EXEC Risk.dbo.CalculateSimpleExposure @ScenarioCode = 'BASE_DOWN_10';
GO
