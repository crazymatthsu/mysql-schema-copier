USE Trading;
GO

MERGE dbo.Account AS target
USING (VALUES
    ('TEST_ALPHA', 'Alpha Synthetic Equity Account', 'USD', 1),
    ('TEST_BETA', 'Beta Long Short Account', 'USD', 1)
) AS source (AccountCode, AccountName, BaseCurrencyCode, IsActive)
ON target.AccountCode = source.AccountCode
WHEN MATCHED THEN UPDATE SET
    AccountName = source.AccountName,
    BaseCurrencyCode = source.BaseCurrencyCode,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT (AccountCode, AccountName, BaseCurrencyCode, IsActive)
    VALUES (source.AccountCode, source.AccountName, source.BaseCurrencyCode, source.IsActive);
GO

MERGE dbo.Trader AS target
USING (VALUES
    ('TRDR_JANE', 'Jane Local', 'EQUITIES', 1),
    ('TRDR_MAX', 'Max Local', 'ETF', 1)
) AS source (TraderCode, DisplayName, DeskCode, IsActive)
ON target.TraderCode = source.TraderCode
WHEN MATCHED THEN UPDATE SET
    DisplayName = source.DisplayName,
    DeskCode = source.DeskCode,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT (TraderCode, DisplayName, DeskCode, IsActive)
    VALUES (source.TraderCode, source.DisplayName, source.DeskCode, source.IsActive);
GO

MERGE dbo.Portfolio AS target
USING (
    SELECT a.AccountId, v.PortfolioCode, v.PortfolioName, v.StrategyCode
    FROM (VALUES
        ('TEST_ALPHA', 'ALPHA_CORE', 'Alpha Core Equity', 'CORE'),
        ('TEST_ALPHA', 'ALPHA_GROWTH', 'Alpha Growth Equity', 'GROWTH'),
        ('TEST_BETA', 'BETA_HEDGE', 'Beta Hedge Book', 'MARKET_NEUTRAL')
    ) AS v (AccountCode, PortfolioCode, PortfolioName, StrategyCode)
    JOIN dbo.Account AS a ON a.AccountCode = v.AccountCode
) AS source
ON target.PortfolioCode = source.PortfolioCode
WHEN MATCHED THEN UPDATE SET
    AccountId = source.AccountId,
    PortfolioName = source.PortfolioName,
    StrategyCode = source.StrategyCode
WHEN NOT MATCHED THEN INSERT (AccountId, PortfolioCode, PortfolioName, StrategyCode)
    VALUES (source.AccountId, source.PortfolioCode, source.PortfolioName, source.StrategyCode);
GO

MERGE dbo.Position AS target
USING (
    SELECT
        a.AccountId,
        p.PortfolioId,
        i.InstrumentId,
        v.Quantity,
        v.AverageCost,
        v.MarketPrice,
        CONVERT(date, SYSUTCDATETIME()) AS AsOfDate
    FROM (VALUES
        ('TEST_ALPHA', 'ALPHA_CORE', 'AAPL', 'XNAS', 1200.00000000, 185.120000, 191.400000),
        ('TEST_ALPHA', 'ALPHA_CORE', 'MSFT', 'XNAS', 800.00000000, 407.330000, 421.850000),
        ('TEST_ALPHA', 'ALPHA_GROWTH', 'NVDA', 'XNAS', 450.00000000, 875.550000, 913.200000),
        ('TEST_BETA', 'BETA_HEDGE', 'SPY', 'ARCX', 1500.00000000, 510.100000, 524.700000),
        ('TEST_BETA', 'BETA_HEDGE', 'TSLA', 'XNAS', -300.00000000, 246.700000, 232.900000)
    ) AS v (AccountCode, PortfolioCode, Symbol, ExchangeCode, Quantity, AverageCost, MarketPrice)
    JOIN dbo.Account AS a ON a.AccountCode = v.AccountCode
    JOIN dbo.Portfolio AS p ON p.PortfolioCode = v.PortfolioCode
    JOIN ReferenceData.dbo.Instrument AS i ON i.Symbol = v.Symbol AND i.ExchangeCode = v.ExchangeCode
) AS source
ON target.AccountId = source.AccountId
   AND target.PortfolioId = source.PortfolioId
   AND target.InstrumentId = source.InstrumentId
   AND target.AsOfDate = source.AsOfDate
WHEN MATCHED THEN UPDATE SET
    Quantity = source.Quantity,
    AverageCost = source.AverageCost,
    MarketPrice = source.MarketPrice,
    UpdatedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (AccountId, PortfolioId, InstrumentId, Quantity, AverageCost, MarketPrice, AsOfDate)
    VALUES (source.AccountId, source.PortfolioId, source.InstrumentId, source.Quantity, source.AverageCost, source.MarketPrice, source.AsOfDate);
GO
