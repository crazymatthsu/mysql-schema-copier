USE Risk;
GO

DROP PROCEDURE IF EXISTS dbo.CalculateSimpleExposure;
DROP TABLE IF EXISTS dbo.PositionRisk;
DROP TABLE IF EXISTS dbo.RiskScenario;
GO

CREATE TABLE dbo.RiskScenario (
    ScenarioCode varchar(32) NOT NULL CONSTRAINT PK_RiskScenario PRIMARY KEY,
    ScenarioName nvarchar(128) NOT NULL,
    EquityShockPct decimal(9, 6) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_RiskScenario_IsActive DEFAULT 1
);
GO

CREATE TABLE dbo.PositionRisk (
    PositionRiskId bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_PositionRisk PRIMARY KEY,
    ScenarioCode varchar(32) NOT NULL,
    AccountCode varchar(32) NOT NULL,
    PortfolioCode varchar(32) NOT NULL,
    InstrumentId int NOT NULL,
    Quantity decimal(28, 8) NOT NULL,
    BaseMarketValue decimal(28, 6) NOT NULL,
    StressedMarketValue decimal(28, 6) NOT NULL,
    CalculatedAt datetime2(3) NOT NULL CONSTRAINT DF_PositionRisk_CalculatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_PositionRisk_Scenario FOREIGN KEY (ScenarioCode) REFERENCES dbo.RiskScenario(ScenarioCode)
);
GO

CREATE INDEX IX_PositionRisk_Scenario ON dbo.PositionRisk(ScenarioCode, AccountCode, PortfolioCode);
GO

CREATE OR ALTER PROCEDURE dbo.CalculateSimpleExposure
    @ScenarioCode varchar(32)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Shock decimal(9, 6);
    SELECT @Shock = EquityShockPct
    FROM dbo.RiskScenario
    WHERE ScenarioCode = @ScenarioCode
      AND IsActive = 1;

    IF @Shock IS NULL
        THROW 53000, 'Unknown active risk scenario.', 1;

    DELETE FROM dbo.PositionRisk
    WHERE ScenarioCode = @ScenarioCode;

    INSERT INTO dbo.PositionRisk (
        ScenarioCode, AccountCode, PortfolioCode, InstrumentId, Quantity,
        BaseMarketValue, StressedMarketValue
    )
    SELECT
        @ScenarioCode,
        p.AccountCode,
        p.PortfolioCode,
        p.InstrumentId,
        p.Quantity,
        p.MarketValue,
        p.MarketValue * (1 + @Shock)
    FROM Trading.dbo.vCurrentPosition AS p
    JOIN ReferenceData.dbo.Instrument AS i ON i.InstrumentId = p.InstrumentId
    WHERE i.InstrumentTypeCode = 'EQUITY';

    SELECT
        ScenarioCode,
        AccountCode,
        SUM(BaseMarketValue) AS BaseMarketValue,
        SUM(StressedMarketValue) AS StressedMarketValue
    FROM dbo.PositionRisk
    WHERE ScenarioCode = @ScenarioCode
    GROUP BY ScenarioCode, AccountCode;
END;
GO
