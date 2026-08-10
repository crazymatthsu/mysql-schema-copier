USE ReferenceData;
GO

MERGE dbo.Currency AS target
USING (VALUES
    ('USD', 'US Dollar', 2, 1),
    ('EUR', 'Euro', 2, 1),
    ('GBP', 'British Pound', 2, 1)
) AS source (CurrencyCode, CurrencyName, MinorUnit, IsActive)
ON target.CurrencyCode = source.CurrencyCode
WHEN MATCHED THEN UPDATE SET
    CurrencyName = source.CurrencyName,
    MinorUnit = source.MinorUnit,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT (CurrencyCode, CurrencyName, MinorUnit, IsActive)
    VALUES (source.CurrencyCode, source.CurrencyName, source.MinorUnit, source.IsActive);
GO

MERGE dbo.Exchange AS target
USING (VALUES
    ('XNYS', 'New York Stock Exchange', 'XNYS', 'America/New_York', 'USD', 1),
    ('XNAS', 'Nasdaq Stock Market', 'XNAS', 'America/New_York', 'USD', 1),
    ('ARCX', 'NYSE Arca', 'ARCX', 'America/New_York', 'USD', 1)
) AS source (ExchangeCode, ExchangeName, MicCode, TimeZoneName, CurrencyCode, IsActive)
ON target.ExchangeCode = source.ExchangeCode
WHEN MATCHED THEN UPDATE SET
    ExchangeName = source.ExchangeName,
    MicCode = source.MicCode,
    TimeZoneName = source.TimeZoneName,
    CurrencyCode = source.CurrencyCode,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT (ExchangeCode, ExchangeName, MicCode, TimeZoneName, CurrencyCode, IsActive)
    VALUES (source.ExchangeCode, source.ExchangeName, source.MicCode, source.TimeZoneName, source.CurrencyCode, source.IsActive);
GO

MERGE dbo.InstrumentType AS target
USING (VALUES
    ('EQUITY', 'Common Equity'),
    ('ETF', 'Exchange Traded Fund'),
    ('BOND', 'Fixed Income')
) AS source (InstrumentTypeCode, InstrumentTypeName)
ON target.InstrumentTypeCode = source.InstrumentTypeCode
WHEN MATCHED THEN UPDATE SET InstrumentTypeName = source.InstrumentTypeName
WHEN NOT MATCHED THEN INSERT (InstrumentTypeCode, InstrumentTypeName)
    VALUES (source.InstrumentTypeCode, source.InstrumentTypeName);
GO

MERGE dbo.Instrument AS target
USING (VALUES
    ('AAPL', 'Apple Inc.', 'EQUITY', 'XNAS', 'USD', '037833100', 'US0378331005', 0.01000000, 1, 1),
    ('MSFT', 'Microsoft Corporation', 'EQUITY', 'XNAS', 'USD', '594918104', 'US5949181045', 0.01000000, 1, 1),
    ('NVDA', 'NVIDIA Corporation', 'EQUITY', 'XNAS', 'USD', '67066G104', 'US67066G1040', 0.01000000, 1, 1),
    ('TSLA', 'Tesla Inc.', 'EQUITY', 'XNAS', 'USD', '88160R101', 'US88160R1014', 0.01000000, 1, 1),
    ('SPY', 'SPDR S&P 500 ETF Trust', 'ETF', 'ARCX', 'USD', '78462F103', 'US78462F1030', 0.01000000, 1, 1)
) AS source (Symbol, InstrumentName, InstrumentTypeCode, ExchangeCode, CurrencyCode, Cusip, Isin, TickSize, LotSize, IsActive)
ON target.Symbol = source.Symbol AND target.ExchangeCode = source.ExchangeCode
WHEN MATCHED THEN UPDATE SET
    InstrumentName = source.InstrumentName,
    InstrumentTypeCode = source.InstrumentTypeCode,
    CurrencyCode = source.CurrencyCode,
    Cusip = source.Cusip,
    Isin = source.Isin,
    TickSize = source.TickSize,
    LotSize = source.LotSize,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT (
    Symbol, InstrumentName, InstrumentTypeCode, ExchangeCode, CurrencyCode, Cusip, Isin, TickSize, LotSize, IsActive
) VALUES (
    source.Symbol, source.InstrumentName, source.InstrumentTypeCode, source.ExchangeCode, source.CurrencyCode,
    source.Cusip, source.Isin, source.TickSize, source.LotSize, source.IsActive
);
GO
