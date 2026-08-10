/*
    ReferenceData - non-clustered indexes.

    Indexes affect plan shape, so a clone that omits them will not reproduce enterprise
    query behaviour even when the data is identical.
*/

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Instrument_Symbol' AND object_id = OBJECT_ID(N'dbo.Instrument'))
    CREATE NONCLUSTERED INDEX IX_Instrument_Symbol
        ON dbo.Instrument (Symbol)
        INCLUDE (ExchangeId, CurrencyCode, IsActive);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Instrument_Active' AND object_id = OBJECT_ID(N'dbo.Instrument'))
    CREATE NONCLUSTERED INDEX IX_Instrument_Active
        ON dbo.Instrument (ExchangeId, Symbol)
        INCLUDE (InstrumentName, CurrencyCode, TickSize, LotSize)
        WHERE IsActive = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Instrument_Isin' AND object_id = OBJECT_ID(N'dbo.Instrument'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Instrument_Isin
        ON dbo.Instrument (Isin)
        WHERE Isin IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PriceSnapshot_AsOfUtc' AND object_id = OBJECT_ID(N'mkt.PriceSnapshot'))
    CREATE NONCLUSTERED INDEX IX_PriceSnapshot_AsOfUtc
        ON mkt.PriceSnapshot (AsOfUtc DESC)
        INCLUDE (InstrumentId, LastPx);
GO
