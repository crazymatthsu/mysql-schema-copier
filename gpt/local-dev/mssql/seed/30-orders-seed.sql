USE Orders;
GO

MERGE dbo.OrderStatus AS target
USING (VALUES
    ('NEW', 'New', 0),
    ('PARTIAL', 'Partially Filled', 0),
    ('FILLED', 'Filled', 1),
    ('CANCELED', 'Canceled', 1),
    ('REJECTED', 'Rejected', 1)
) AS source (OrderStatusCode, StatusName, IsTerminal)
ON target.OrderStatusCode = source.OrderStatusCode
WHEN MATCHED THEN UPDATE SET StatusName = source.StatusName, IsTerminal = source.IsTerminal
WHEN NOT MATCHED THEN INSERT (OrderStatusCode, StatusName, IsTerminal)
    VALUES (source.OrderStatusCode, source.StatusName, source.IsTerminal);
GO

MERGE dbo.OrderType AS target
USING (VALUES
    ('MKT', 'Market'),
    ('LMT', 'Limit'),
    ('STOP', 'Stop')
) AS source (OrderTypeCode, TypeName)
ON target.OrderTypeCode = source.OrderTypeCode
WHEN MATCHED THEN UPDATE SET TypeName = source.TypeName
WHEN NOT MATCHED THEN INSERT (OrderTypeCode, TypeName)
    VALUES (source.OrderTypeCode, source.TypeName);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.EquityOrder WHERE ClientOrderId = 'LOCAL-CLORD-0001')
BEGIN
    EXEC dbo.CreateEquityOrder
        @ClientOrderId = 'LOCAL-CLORD-0001',
        @AccountCode = 'TEST_ALPHA',
        @PortfolioCode = 'ALPHA_CORE',
        @TraderCode = 'TRDR_JANE',
        @Symbol = 'AAPL',
        @ExchangeCode = 'XNAS',
        @Side = 'B',
        @OrderTypeCode = 'LMT',
        @TimeInForce = 'DAY',
        @OrderQty = 100.00000000,
        @LimitPrice = 192.000000;
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.EquityOrder WHERE ClientOrderId = 'LOCAL-CLORD-0002')
BEGIN
    EXEC dbo.CreateEquityOrder
        @ClientOrderId = 'LOCAL-CLORD-0002',
        @AccountCode = 'TEST_BETA',
        @PortfolioCode = 'BETA_HEDGE',
        @TraderCode = 'TRDR_MAX',
        @Symbol = 'TSLA',
        @ExchangeCode = 'XNAS',
        @Side = 'S',
        @OrderTypeCode = 'MKT',
        @TimeInForce = 'DAY',
        @OrderQty = 50.00000000,
        @LimitPrice = NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ExecutionReport WHERE ExecId = 'LOCAL-EXEC-0001')
BEGIN
    EXEC dbo.ApplyExecution
        @ClientOrderId = 'LOCAL-CLORD-0001',
        @ExecId = 'LOCAL-EXEC-0001',
        @ExecQty = 40.00000000,
        @ExecPrice = 191.750000,
        @LiquidityFlag = 'A',
        @VenueCode = 'XNAS';
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ExecutionReport WHERE ExecId = 'LOCAL-EXEC-0002')
BEGIN
    EXEC dbo.ApplyExecution
        @ClientOrderId = 'LOCAL-CLORD-0002',
        @ExecId = 'LOCAL-EXEC-0002',
        @ExecQty = 50.00000000,
        @ExecPrice = 232.500000,
        @LiquidityFlag = 'R',
        @VenueCode = 'XNAS';
END
GO
