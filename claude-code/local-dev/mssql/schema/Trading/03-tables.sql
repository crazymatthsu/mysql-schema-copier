/*
    Trading - tables.

    Positions and cash are derived state: they are only ever mutated through
    dbo.usp_ApplyExecution, which the Orders database calls after every fill.

    NOTE ON CROSS-DATABASE KEYS
    InstrumentId points at ReferenceData.dbo.Instrument. SQL Server cannot enforce a
    foreign key across databases, so the reference is validated inside
    dbo.usp_ApplyExecution instead. This is exactly the kind of dependency that has to
    be verified explicitly when cloning a schema - a DACPAC will not flag it.
*/

IF OBJECT_ID(N'dbo.Book', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Book
    (
        BookId        INT           NOT NULL IDENTITY(1, 1),
        BookCode      VARCHAR(20)   NOT NULL,
        BookName      NVARCHAR(80)  NOT NULL,
        DeskCode      VARCHAR(20)   NOT NULL,
        BaseCurrency  CHAR(3)       NOT NULL,
        IsActive      BIT           NOT NULL CONSTRAINT DF_Book_IsActive DEFAULT (1),
        CONSTRAINT PK_Book PRIMARY KEY CLUSTERED (BookId),
        CONSTRAINT UQ_Book_BookCode UNIQUE (BookCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.Trader', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Trader
    (
        TraderId    INT           NOT NULL IDENTITY(1, 1),
        TraderCode  VARCHAR(20)   NOT NULL,
        TraderName  NVARCHAR(80)  NOT NULL,
        DeskCode    VARCHAR(20)   NOT NULL,
        IsActive    BIT           NOT NULL CONSTRAINT DF_Trader_IsActive DEFAULT (1),
        CONSTRAINT PK_Trader PRIMARY KEY CLUSTERED (TraderId),
        CONSTRAINT UQ_Trader_TraderCode UNIQUE (TraderCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.Account', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Account
    (
        AccountId     INT           NOT NULL,
        AccountCode   VARCHAR(20)   NOT NULL,
        AccountName   NVARCHAR(80)  NOT NULL,
        AccountType   VARCHAR(10)   NOT NULL,
        BaseCurrency  CHAR(3)       NOT NULL,
        BookId        INT           NULL,
        IsActive      BIT           NOT NULL CONSTRAINT DF_Account_IsActive DEFAULT (1),
        CreatedAtUtc  DATETIME2(3)  NOT NULL CONSTRAINT DF_Account_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Account PRIMARY KEY CLUSTERED (AccountId),
        CONSTRAINT UQ_Account_AccountCode UNIQUE (AccountCode),
        CONSTRAINT FK_Account_Book FOREIGN KEY (BookId) REFERENCES dbo.Book (BookId),
        CONSTRAINT CK_Account_Type CHECK (AccountType IN ('CLIENT', 'FIRM', 'HEDGE'))
    );
END;
GO

IF OBJECT_ID(N'dbo.Position', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Position
    (
        AccountId     INT             NOT NULL,
        InstrumentId  INT             NOT NULL,  -- ReferenceData.dbo.Instrument (cross-database)
        Quantity      DECIMAL(19, 4)  NOT NULL CONSTRAINT DF_Position_Quantity DEFAULT (0),
        AvgPrice      DECIMAL(19, 6)  NOT NULL CONSTRAINT DF_Position_AvgPrice DEFAULT (0),
        RealizedPnL   DECIMAL(19, 4)  NOT NULL CONSTRAINT DF_Position_RealizedPnL DEFAULT (0),
        LastExecId    VARCHAR(36)     NULL,
        UpdatedAtUtc  DATETIME2(3)    NOT NULL CONSTRAINT DF_Position_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Position PRIMARY KEY CLUSTERED (AccountId, InstrumentId),
        CONSTRAINT FK_Position_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account (AccountId),
        CONSTRAINT CK_Position_AvgPrice CHECK (AvgPrice >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.PositionHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PositionHistory
    (
        HistoryId     BIGINT          NOT NULL IDENTITY(1, 1),
        AccountId     INT             NOT NULL,
        InstrumentId  INT             NOT NULL,
        ChangeType    CHAR(1)         NOT NULL,
        Quantity      DECIMAL(19, 4)  NOT NULL,
        AvgPrice      DECIMAL(19, 6)  NOT NULL,
        RealizedPnL   DECIMAL(19, 4)  NOT NULL,
        ChangedAtUtc  DATETIME2(3)    NOT NULL CONSTRAINT DF_PositionHistory_ChangedAtUtc DEFAULT (SYSUTCDATETIME()),
        ChangedBy     SYSNAME         NOT NULL CONSTRAINT DF_PositionHistory_ChangedBy DEFAULT (SUSER_SNAME()),
        CONSTRAINT PK_PositionHistory PRIMARY KEY CLUSTERED (HistoryId),
        CONSTRAINT CK_PositionHistory_ChangeType CHECK (ChangeType IN ('I', 'U', 'D'))
    );
END;
GO

IF OBJECT_ID(N'dbo.CashBalance', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CashBalance
    (
        AccountId     INT             NOT NULL,
        CurrencyCode  CHAR(3)         NOT NULL,
        Amount        DECIMAL(19, 4)  NOT NULL CONSTRAINT DF_CashBalance_Amount DEFAULT (0),
        UpdatedAtUtc  DATETIME2(3)    NOT NULL CONSTRAINT DF_CashBalance_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_CashBalance PRIMARY KEY CLUSTERED (AccountId, CurrencyCode),
        CONSTRAINT FK_CashBalance_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account (AccountId)
    );
END;
GO
