/*
    Orders - tables.

    dbo.[Order] is deliberately named with a reserved word, as it is upstream: quoting
    behaviour (QUOTED_IDENTIFIER, bracketed names in JDBC) is one of the things a local
    clone needs to reproduce faithfully.

    AccountId, TraderId and InstrumentId are cross-database references (Trading and
    ReferenceData) and therefore cannot carry a foreign key. They are validated in
    dbo.usp_PlaceOrder.
*/

IF OBJECT_ID(N'dbo.OrderSide', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderSide
    (
        SideCode     VARCHAR(4)    NOT NULL,
        Description  NVARCHAR(40)  NOT NULL,
        CONSTRAINT PK_OrderSide PRIMARY KEY CLUSTERED (SideCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.OrderType', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderType
    (
        OrderTypeCode  VARCHAR(10)   NOT NULL,
        Description    NVARCHAR(40)  NOT NULL,
        RequiresLimit  BIT           NOT NULL CONSTRAINT DF_OrderType_RequiresLimit DEFAULT (0),
        RequiresStop   BIT           NOT NULL CONSTRAINT DF_OrderType_RequiresStop DEFAULT (0),
        CONSTRAINT PK_OrderType PRIMARY KEY CLUSTERED (OrderTypeCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.TimeInForce', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TimeInForce
    (
        TifCode      VARCHAR(3)    NOT NULL,
        Description  NVARCHAR(40)  NOT NULL,
        CONSTRAINT PK_TimeInForce PRIMARY KEY CLUSTERED (TifCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.OrderStatus', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderStatus
    (
        StatusCode   VARCHAR(20)   NOT NULL,
        Description  NVARCHAR(40)  NOT NULL,
        IsTerminal   BIT           NOT NULL CONSTRAINT DF_OrderStatus_IsTerminal DEFAULT (0),
        CONSTRAINT PK_OrderStatus PRIMARY KEY CLUSTERED (StatusCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.[Order]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Order]
    (
        OrderId        BIGINT          NOT NULL
            CONSTRAINT DF_Order_OrderId DEFAULT (NEXT VALUE FOR dbo.OrderIdSeq),
        ClOrdId        VARCHAR(36)     NOT NULL,
        ParentOrderId  BIGINT          NULL,
        AccountId      INT             NOT NULL,  -- Trading.dbo.Account (cross-database)
        InstrumentId   INT             NOT NULL,  -- ReferenceData.dbo.Instrument (cross-database)
        TraderId       INT             NULL,      -- Trading.dbo.Trader (cross-database)
        SideCode       VARCHAR(4)      NOT NULL,
        OrderTypeCode  VARCHAR(10)     NOT NULL,
        TifCode        VARCHAR(3)      NOT NULL,
        StatusCode     VARCHAR(20)     NOT NULL,
        OrderQty       DECIMAL(19, 4)  NOT NULL,
        LimitPrice     DECIMAL(19, 6)  NULL,
        StopPrice      DECIMAL(19, 6)  NULL,
        LeavesQty      DECIMAL(19, 4)  NOT NULL,
        CumQty         DECIMAL(19, 4)  NOT NULL CONSTRAINT DF_Order_CumQty DEFAULT (0),
        AvgPx          DECIMAL(19, 6)  NOT NULL CONSTRAINT DF_Order_AvgPx DEFAULT (0),
        Venue          VARCHAR(10)     NULL,
        RejectReason   VARCHAR(40)     NULL,
        CreatedAtUtc   DATETIME2(3)    NOT NULL CONSTRAINT DF_Order_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc   DATETIME2(3)    NOT NULL CONSTRAINT DF_Order_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        RowVersion     ROWVERSION      NOT NULL,
        CONSTRAINT PK_Order PRIMARY KEY CLUSTERED (OrderId),
        CONSTRAINT UQ_Order_ClOrdId UNIQUE (ClOrdId),
        CONSTRAINT FK_Order_Parent FOREIGN KEY (ParentOrderId) REFERENCES dbo.[Order] (OrderId),
        CONSTRAINT FK_Order_Side FOREIGN KEY (SideCode) REFERENCES dbo.OrderSide (SideCode),
        CONSTRAINT FK_Order_Type FOREIGN KEY (OrderTypeCode) REFERENCES dbo.OrderType (OrderTypeCode),
        CONSTRAINT FK_Order_Tif FOREIGN KEY (TifCode) REFERENCES dbo.TimeInForce (TifCode),
        CONSTRAINT FK_Order_Status FOREIGN KEY (StatusCode) REFERENCES dbo.OrderStatus (StatusCode),
        CONSTRAINT CK_Order_OrderQty CHECK (OrderQty > 0),
        CONSTRAINT CK_Order_Fills CHECK (CumQty >= 0 AND LeavesQty >= 0 AND CumQty + LeavesQty <= OrderQty),
        CONSTRAINT CK_Order_Prices CHECK
        (
            (LimitPrice IS NULL OR LimitPrice > 0)
            AND (StopPrice IS NULL OR StopPrice > 0)
        )
    );
END;
GO

IF OBJECT_ID(N'dbo.Execution', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Execution
    (
        ExecutionId     BIGINT          NOT NULL
            CONSTRAINT DF_Execution_ExecutionId DEFAULT (NEXT VALUE FOR dbo.ExecutionIdSeq),
        ExecId          VARCHAR(36)     NOT NULL,
        OrderId         BIGINT          NOT NULL,
        ExecType        VARCHAR(12)     NOT NULL,
        LastQty         DECIMAL(19, 4)  NOT NULL,
        LastPx          DECIMAL(19, 6)  NOT NULL,
        TradeDate       DATE            NOT NULL,
        SettlementDate  DATE            NULL,
        VenueExecId     VARCHAR(40)     NULL,
        LiquidityFlag   CHAR(1)         NULL,
        Commission      DECIMAL(19, 4)  NOT NULL CONSTRAINT DF_Execution_Commission DEFAULT (0),
        CreatedAtUtc    DATETIME2(3)    NOT NULL CONSTRAINT DF_Execution_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Execution PRIMARY KEY CLUSTERED (ExecutionId),
        CONSTRAINT UQ_Execution_ExecId UNIQUE (ExecId),
        CONSTRAINT FK_Execution_Order FOREIGN KEY (OrderId) REFERENCES dbo.[Order] (OrderId),
        CONSTRAINT CK_Execution_LastQty CHECK (LastQty > 0),
        CONSTRAINT CK_Execution_LastPx CHECK (LastPx > 0),
        CONSTRAINT CK_Execution_ExecType CHECK (ExecType IN ('TRADE', 'TRADE_CORRECT', 'TRADE_CANCEL')),
        CONSTRAINT CK_Execution_Liquidity CHECK (LiquidityFlag IS NULL OR LiquidityFlag IN ('A', 'R'))
    );
END;
GO

IF OBJECT_ID(N'audit.OrderEvent', N'U') IS NULL
BEGIN
    CREATE TABLE audit.OrderEvent
    (
        EventId        BIGINT          NOT NULL IDENTITY(1, 1),
        OrderId        BIGINT          NOT NULL,
        EventType      VARCHAR(20)     NOT NULL,
        OldStatusCode  VARCHAR(20)     NULL,
        NewStatusCode  VARCHAR(20)     NULL,
        OldLeavesQty   DECIMAL(19, 4)  NULL,
        NewLeavesQty   DECIMAL(19, 4)  NULL,
        OldCumQty      DECIMAL(19, 4)  NULL,
        NewCumQty      DECIMAL(19, 4)  NULL,
        EventAtUtc     DATETIME2(3)    NOT NULL CONSTRAINT DF_OrderEvent_EventAtUtc DEFAULT (SYSUTCDATETIME()),
        EventBy        SYSNAME         NOT NULL CONSTRAINT DF_OrderEvent_EventBy DEFAULT (SUSER_SNAME()),
        CONSTRAINT PK_OrderEvent PRIMARY KEY CLUSTERED (EventId)
    );
END;
GO
