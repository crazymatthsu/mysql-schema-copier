/*
    ReferenceData - stored procedures.
*/

CREATE OR ALTER PROCEDURE dbo.usp_GetInstrument
    @Symbol VARCHAR(20),
    @Mic    CHAR(4) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        v.InstrumentId,
        v.Symbol,
        v.Isin,
        v.InstrumentName,
        v.InstrumentType,
        v.CurrencyCode,
        v.LotSize,
        v.TickSize,
        v.Mic,
        v.ExchangeName
    FROM dbo.vw_ActiveInstrument AS v
    WHERE v.Symbol = @Symbol
      AND (@Mic IS NULL OR v.Mic = @Mic)
    ORDER BY v.Mic;
END;
GO

/*
    MERGE-based upsert. The nightly reference-data feed replays the full instrument
    universe, so the local clone has to support the same statement.
*/
CREATE OR ALTER PROCEDURE dbo.usp_UpsertInstrument
    @Symbol         VARCHAR(20),
    @Mic            CHAR(4),
    @InstrumentName NVARCHAR(120),
    @InstrumentType VARCHAR(10),
    @CurrencyCode   CHAR(3),
    @Isin           CHAR(12)       = NULL,
    @Cusip          CHAR(9)        = NULL,
    @SectorCode     VARCHAR(20)    = NULL,
    @LotSize        INT            = 1,
    @TickSize       DECIMAL(19, 6) = 0.01,
    @IsActive       BIT            = 1,
    @InstrumentId   INT            = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExchangeId INT =
    (
        SELECT e.ExchangeId FROM dbo.Exchange AS e WHERE e.Mic = @Mic
    );

    IF @ExchangeId IS NULL
        THROW 51001, 'Unknown MIC passed to usp_UpsertInstrument.', 1;

    DECLARE @Affected TABLE (InstrumentId INT NOT NULL);

    MERGE dbo.Instrument WITH (HOLDLOCK) AS tgt
    USING
    (
        SELECT
            ExchangeId = @ExchangeId,
            Symbol     = @Symbol
    ) AS src
        ON tgt.ExchangeId = src.ExchangeId
       AND tgt.Symbol = src.Symbol
    WHEN MATCHED THEN
        UPDATE SET
            tgt.InstrumentName = @InstrumentName,
            tgt.InstrumentType = @InstrumentType,
            tgt.CurrencyCode   = @CurrencyCode,
            tgt.Isin           = @Isin,
            tgt.Cusip          = @Cusip,
            tgt.SectorCode     = @SectorCode,
            tgt.LotSize        = @LotSize,
            tgt.TickSize       = @TickSize,
            tgt.IsActive       = @IsActive
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Symbol, Isin, Cusip, InstrumentName, InstrumentType, ExchangeId,
                CurrencyCode, SectorCode, LotSize, TickSize, IsActive)
        VALUES (@Symbol, @Isin, @Cusip, @InstrumentName, @InstrumentType, @ExchangeId,
                @CurrencyCode, @SectorCode, @LotSize, @TickSize, @IsActive)
    OUTPUT inserted.InstrumentId INTO @Affected (InstrumentId);

    SELECT @InstrumentId = MAX(InstrumentId) FROM @Affected;
END;
GO

CREATE OR ALTER PROCEDURE mkt.usp_UpsertPriceSnapshot
    @InstrumentId INT,
    @AsOfUtc      DATETIME2(3),
    @LastPx       DECIMAL(19, 6),
    @BidPx        DECIMAL(19, 6) = NULL,
    @AskPx        DECIMAL(19, 6) = NULL,
    @VolumeTraded BIGINT         = 0,
    @Source       VARCHAR(20)    = 'SYNTHETIC'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    MERGE mkt.PriceSnapshot WITH (HOLDLOCK) AS tgt
    USING
    (
        SELECT
            InstrumentId = @InstrumentId,
            AsOfUtc      = @AsOfUtc
    ) AS src
        ON tgt.InstrumentId = src.InstrumentId
       AND tgt.AsOfUtc = src.AsOfUtc
    WHEN MATCHED THEN
        UPDATE SET
            tgt.LastPx       = @LastPx,
            tgt.BidPx        = @BidPx,
            tgt.AskPx        = @AskPx,
            tgt.VolumeTraded = @VolumeTraded,
            tgt.Source       = @Source
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (InstrumentId, AsOfUtc, BidPx, AskPx, LastPx, VolumeTraded, Source)
        VALUES (@InstrumentId, @AsOfUtc, @BidPx, @AskPx, @LastPx, @VolumeTraded, @Source);
END;
GO
