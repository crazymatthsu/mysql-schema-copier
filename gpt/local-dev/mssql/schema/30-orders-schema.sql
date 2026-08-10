USE Orders;
GO

DROP PROCEDURE IF EXISTS dbo.ApplyExecution;
DROP PROCEDURE IF EXISTS dbo.CreateEquityOrder;
DROP VIEW IF EXISTS dbo.vOrderBlotter;
DROP TABLE IF EXISTS dbo.ExecutionReport;
DROP TABLE IF EXISTS dbo.EquityOrder;
DROP TABLE IF EXISTS dbo.OrderType;
DROP TABLE IF EXISTS dbo.OrderStatus;
DROP SEQUENCE IF EXISTS dbo.OrderNumberSequence;
GO

CREATE SEQUENCE dbo.OrderNumberSequence
    AS bigint
    START WITH 100000
    INCREMENT BY 1;
GO

CREATE TABLE dbo.OrderStatus (
    OrderStatusCode varchar(16) NOT NULL CONSTRAINT PK_OrderStatus PRIMARY KEY,
    StatusName nvarchar(64) NOT NULL,
    IsTerminal bit NOT NULL
);
GO

CREATE TABLE dbo.OrderType (
    OrderTypeCode varchar(16) NOT NULL CONSTRAINT PK_OrderType PRIMARY KEY,
    TypeName nvarchar(64) NOT NULL
);
GO

CREATE TABLE dbo.EquityOrder (
    OrderId bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_EquityOrder PRIMARY KEY,
    OrderNumber bigint NOT NULL CONSTRAINT DF_EquityOrder_OrderNumber DEFAULT NEXT VALUE FOR dbo.OrderNumberSequence,
    ClientOrderId varchar(64) NOT NULL,
    AccountCode varchar(32) NOT NULL,
    PortfolioCode varchar(32) NOT NULL,
    TraderCode varchar(32) NOT NULL,
    InstrumentId int NOT NULL,
    Side char(1) NOT NULL,
    OrderTypeCode varchar(16) NOT NULL,
    TimeInForce varchar(8) NOT NULL,
    OrderQty decimal(28, 8) NOT NULL,
    LeavesQty decimal(28, 8) NOT NULL,
    CumQty decimal(28, 8) NOT NULL CONSTRAINT DF_EquityOrder_CumQty DEFAULT 0,
    LimitPrice decimal(19, 6) NULL,
    StopPrice decimal(19, 6) NULL,
    OrderStatusCode varchar(16) NOT NULL,
    CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_EquityOrder_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt datetime2(3) NOT NULL CONSTRAINT DF_EquityOrder_UpdatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_EquityOrder_ClientOrderId UNIQUE (ClientOrderId),
    CONSTRAINT CK_EquityOrder_Side CHECK (Side IN ('B', 'S')),
    CONSTRAINT CK_EquityOrder_Qty CHECK (OrderQty > 0 AND LeavesQty >= 0 AND CumQty >= 0),
    CONSTRAINT FK_EquityOrder_Status FOREIGN KEY (OrderStatusCode) REFERENCES dbo.OrderStatus(OrderStatusCode),
    CONSTRAINT FK_EquityOrder_Type FOREIGN KEY (OrderTypeCode) REFERENCES dbo.OrderType(OrderTypeCode)
);
GO

CREATE TABLE dbo.ExecutionReport (
    ExecutionId bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_ExecutionReport PRIMARY KEY,
    OrderId bigint NOT NULL,
    ExecId varchar(64) NOT NULL,
    ExecQty decimal(28, 8) NOT NULL,
    ExecPrice decimal(19, 6) NOT NULL,
    LiquidityFlag char(1) NOT NULL,
    VenueCode varchar(12) NOT NULL,
    ExecTime datetime2(3) NOT NULL,
    CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_ExecutionReport_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_ExecutionReport_ExecId UNIQUE (ExecId),
    CONSTRAINT CK_ExecutionReport_QtyPrice CHECK (ExecQty > 0 AND ExecPrice > 0),
    CONSTRAINT CK_ExecutionReport_Liquidity CHECK (LiquidityFlag IN ('A', 'R')),
    CONSTRAINT FK_ExecutionReport_Order FOREIGN KEY (OrderId) REFERENCES dbo.EquityOrder(OrderId)
);
GO

CREATE INDEX IX_EquityOrder_Status ON dbo.EquityOrder(OrderStatusCode, CreatedAt);
CREATE INDEX IX_ExecutionReport_Order ON dbo.ExecutionReport(OrderId, ExecTime);
GO

CREATE OR ALTER VIEW dbo.vOrderBlotter
AS
SELECT
    o.OrderId,
    o.OrderNumber,
    o.ClientOrderId,
    o.AccountCode,
    o.PortfolioCode,
    o.TraderCode,
    o.InstrumentId,
    i.Symbol,
    i.ExchangeCode,
    o.Side,
    o.OrderTypeCode,
    o.OrderQty,
    o.CumQty,
    o.LeavesQty,
    o.LimitPrice,
    o.OrderStatusCode,
    o.CreatedAt,
    o.UpdatedAt
FROM dbo.EquityOrder AS o
JOIN ReferenceData.dbo.Instrument AS i ON i.InstrumentId = o.InstrumentId;
GO

CREATE OR ALTER PROCEDURE dbo.CreateEquityOrder
    @ClientOrderId varchar(64),
    @AccountCode varchar(32),
    @PortfolioCode varchar(32),
    @TraderCode varchar(32),
    @Symbol varchar(32),
    @ExchangeCode varchar(12),
    @Side char(1),
    @OrderTypeCode varchar(16),
    @TimeInForce varchar(8),
    @OrderQty decimal(28, 8),
    @LimitPrice decimal(19, 6) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InstrumentId int;
    SELECT @InstrumentId = InstrumentId
    FROM ReferenceData.dbo.Instrument
    WHERE Symbol = @Symbol
      AND ExchangeCode = @ExchangeCode
      AND IsActive = 1;

    IF @InstrumentId IS NULL
        THROW 52000, 'Unknown active instrument.', 1;

    INSERT INTO dbo.EquityOrder (
        ClientOrderId, AccountCode, PortfolioCode, TraderCode, InstrumentId, Side,
        OrderTypeCode, TimeInForce, OrderQty, LeavesQty, LimitPrice, OrderStatusCode
    )
    VALUES (
        @ClientOrderId, @AccountCode, @PortfolioCode, @TraderCode, @InstrumentId, @Side,
        @OrderTypeCode, @TimeInForce, @OrderQty, @OrderQty, @LimitPrice, 'NEW'
    );

    SELECT SCOPE_IDENTITY() AS OrderId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.ApplyExecution
    @ClientOrderId varchar(64),
    @ExecId varchar(64),
    @ExecQty decimal(28, 8),
    @ExecPrice decimal(19, 6),
    @LiquidityFlag char(1),
    @VenueCode varchar(12)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderId bigint;
    DECLARE @Side char(1);
    DECLARE @InstrumentId int;
    DECLARE @AccountCode varchar(32);
    DECLARE @PortfolioCode varchar(32);

    SELECT
        @OrderId = OrderId,
        @Side = Side,
        @InstrumentId = InstrumentId,
        @AccountCode = AccountCode,
        @PortfolioCode = PortfolioCode
    FROM dbo.EquityOrder
    WHERE ClientOrderId = @ClientOrderId;

    IF @OrderId IS NULL
        THROW 52001, 'Unknown order.', 1;

    INSERT INTO dbo.ExecutionReport (
        OrderId, ExecId, ExecQty, ExecPrice, LiquidityFlag, VenueCode, ExecTime
    )
    VALUES (
        @OrderId, @ExecId, @ExecQty, @ExecPrice, @LiquidityFlag, @VenueCode, SYSUTCDATETIME()
    );

    UPDATE dbo.EquityOrder
    SET CumQty = CumQty + @ExecQty,
        LeavesQty = LeavesQty - @ExecQty,
        OrderStatusCode = CASE
            WHEN LeavesQty - @ExecQty = 0 THEN 'FILLED'
            ELSE 'PARTIAL'
        END,
        UpdatedAt = SYSUTCDATETIME()
    WHERE OrderId = @OrderId;

    EXEC Trading.dbo.ApplyTradeAllocation
        @AccountCode = @AccountCode,
        @PortfolioCode = @PortfolioCode,
        @InstrumentId = @InstrumentId,
        @QuantityDelta = CASE WHEN @Side = 'B' THEN @ExecQty ELSE -@ExecQty END,
        @ExecutionPrice = @ExecPrice;
END;
GO
