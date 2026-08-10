USE Trading;
GO

DROP PROCEDURE IF EXISTS dbo.ApplyTradeAllocation;
DROP VIEW IF EXISTS dbo.vCurrentPosition;
DROP TABLE IF EXISTS dbo.Position;
DROP TABLE IF EXISTS dbo.Portfolio;
DROP TABLE IF EXISTS dbo.Trader;
DROP TABLE IF EXISTS dbo.Account;
GO

CREATE TABLE dbo.Account (
    AccountId int IDENTITY(1000, 1) NOT NULL CONSTRAINT PK_Account PRIMARY KEY,
    AccountCode varchar(32) NOT NULL CONSTRAINT UQ_Account_AccountCode UNIQUE,
    AccountName nvarchar(128) NOT NULL,
    BaseCurrencyCode char(3) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Account_IsActive DEFAULT 1,
    CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_Account_CreatedAt DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.Trader (
    TraderId int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Trader PRIMARY KEY,
    TraderCode varchar(32) NOT NULL CONSTRAINT UQ_Trader_TraderCode UNIQUE,
    DisplayName nvarchar(128) NOT NULL,
    DeskCode varchar(32) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Trader_IsActive DEFAULT 1
);
GO

CREATE TABLE dbo.Portfolio (
    PortfolioId int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Portfolio PRIMARY KEY,
    AccountId int NOT NULL,
    PortfolioCode varchar(32) NOT NULL,
    PortfolioName nvarchar(128) NOT NULL,
    StrategyCode varchar(32) NOT NULL,
    CONSTRAINT UQ_Portfolio_Code UNIQUE (PortfolioCode),
    CONSTRAINT FK_Portfolio_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account(AccountId)
);
GO

CREATE TABLE dbo.Position (
    PositionId bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Position PRIMARY KEY,
    AccountId int NOT NULL,
    PortfolioId int NOT NULL,
    InstrumentId int NOT NULL,
    Quantity decimal(28, 8) NOT NULL,
    AverageCost decimal(19, 6) NOT NULL,
    MarketPrice decimal(19, 6) NOT NULL,
    AsOfDate date NOT NULL,
    UpdatedAt datetime2(3) NOT NULL CONSTRAINT DF_Position_UpdatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Position_BusinessKey UNIQUE (AccountId, PortfolioId, InstrumentId, AsOfDate),
    CONSTRAINT FK_Position_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account(AccountId),
    CONSTRAINT FK_Position_Portfolio FOREIGN KEY (PortfolioId) REFERENCES dbo.Portfolio(PortfolioId)
);
GO

CREATE INDEX IX_Position_Instrument ON dbo.Position(InstrumentId, AsOfDate);
GO

CREATE OR ALTER VIEW dbo.vCurrentPosition
AS
SELECT
    p.PositionId,
    a.AccountCode,
    pf.PortfolioCode,
    p.InstrumentId,
    p.Quantity,
    p.AverageCost,
    p.MarketPrice,
    p.Quantity * p.MarketPrice AS MarketValue,
    p.AsOfDate
FROM dbo.Position AS p
JOIN dbo.Account AS a ON a.AccountId = p.AccountId
JOIN dbo.Portfolio AS pf ON pf.PortfolioId = p.PortfolioId
WHERE p.AsOfDate = CONVERT(date, SYSUTCDATETIME());
GO

CREATE OR ALTER PROCEDURE dbo.ApplyTradeAllocation
    @AccountCode varchar(32),
    @PortfolioCode varchar(32),
    @InstrumentId int,
    @QuantityDelta decimal(28, 8),
    @ExecutionPrice decimal(19, 6)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId int;
    DECLARE @PortfolioId int;
    DECLARE @AsOfDate date = CONVERT(date, SYSUTCDATETIME());

    SELECT @AccountId = AccountId
    FROM dbo.Account
    WHERE AccountCode = @AccountCode;

    SELECT @PortfolioId = PortfolioId
    FROM dbo.Portfolio
    WHERE PortfolioCode = @PortfolioCode;

    IF @AccountId IS NULL OR @PortfolioId IS NULL
        THROW 51000, 'Unknown account or portfolio.', 1;

    MERGE dbo.Position AS target
    USING (
        SELECT @AccountId AS AccountId,
               @PortfolioId AS PortfolioId,
               @InstrumentId AS InstrumentId,
               @AsOfDate AS AsOfDate
    ) AS source
    ON target.AccountId = source.AccountId
       AND target.PortfolioId = source.PortfolioId
       AND target.InstrumentId = source.InstrumentId
       AND target.AsOfDate = source.AsOfDate
    WHEN MATCHED THEN
        UPDATE SET
            Quantity = target.Quantity + @QuantityDelta,
            AverageCost = CASE
                WHEN target.Quantity + @QuantityDelta = 0 THEN 0
                ELSE ((target.Quantity * target.AverageCost) + (@QuantityDelta * @ExecutionPrice))
                     / NULLIF(target.Quantity + @QuantityDelta, 0)
            END,
            MarketPrice = @ExecutionPrice,
            UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (AccountId, PortfolioId, InstrumentId, Quantity, AverageCost, MarketPrice, AsOfDate)
        VALUES (@AccountId, @PortfolioId, @InstrumentId, @QuantityDelta, @ExecutionPrice, @ExecutionPrice, @AsOfDate);
END;
GO
