/*
    ReferenceData - synthetic market data.

    Three snapshots per instrument at fixed times on the current UTC date, so a re-run
    on the same day updates in place rather than growing the table without bound.
*/

DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @Open  DATETIME2(3) = DATEADD(HOUR, 14, CAST(@Today AS DATETIME2(3)));

;WITH BasePrice AS
(
    SELECT *
    FROM
    (
        VALUES
            ('AAPL',   232.50), ('MSFT',  428.90), ('AMZN',  186.40), ('GOOGL', 168.25),
            ('NVDA',   126.80), ('META',  562.10), ('TSLA',  248.60), ('INTC',   22.35),
            ('CSCO',    56.70), ('QQQ',   486.20), ('IBM',   224.15), ('JPM',   221.40),
            ('XOM',    118.65), ('KO',     70.20), ('PFE',    28.95), ('WMT',    82.40),
            ('DIS',     96.30), ('BA',    152.80), ('CVX',   152.10), ('SPY',   571.35),
            ('VOD',      0.75), ('HSBA',    7.12), ('BP',      4.05), ('RIO',    52.80),
            ('AZN',    118.40), ('7203',  2850.0), ('6758',  2960.0), ('9984',  8420.0),
            ('0700',   402.60), ('0005',   68.45), ('RY',    168.20), ('TD',     78.35)
    ) AS v (Symbol, BasePx)
),
Offsets AS
(
    SELECT *
    FROM
    (
        VALUES
            (0, 0.9955, 1),
            (1, 1.0018, 2),
            (2, 1.0000, 3)
    ) AS v (SlotNo, PxFactor, HourOffset)
),
Snapshot AS
(
    SELECT
        i.InstrumentId,
        AsOfUtc = DATEADD(HOUR, o.HourOffset, @Open),
        LastPx  = CAST(b.BasePx * o.PxFactor AS DECIMAL(19, 6)),
        i.TickSize,
        /* Deterministic pseudo-volume: no randomness, so seeded data is reproducible. */
        VolumeTraded = CAST((i.InstrumentId % 37 + 5) * 10000 + o.SlotNo * 2500 AS BIGINT)
    FROM dbo.Instrument AS i
    INNER JOIN BasePrice AS b
        ON b.Symbol = i.Symbol
    CROSS JOIN Offsets AS o
)
MERGE mkt.PriceSnapshot AS tgt
USING
(
    SELECT
        s.InstrumentId,
        s.AsOfUtc,
        LastPx = dbo.ufn_RoundToTick(s.LastPx, s.TickSize),
        BidPx  = dbo.ufn_RoundToTick(s.LastPx - s.TickSize, s.TickSize),
        AskPx  = dbo.ufn_RoundToTick(s.LastPx + s.TickSize, s.TickSize),
        s.VolumeTraded
    FROM Snapshot AS s
) AS src
    ON tgt.InstrumentId = src.InstrumentId
   AND tgt.AsOfUtc = src.AsOfUtc
WHEN MATCHED THEN
    UPDATE SET
        tgt.LastPx       = src.LastPx,
        tgt.BidPx        = src.BidPx,
        tgt.AskPx        = src.AskPx,
        tgt.VolumeTraded = src.VolumeTraded
WHEN NOT MATCHED BY TARGET THEN
    INSERT (InstrumentId, AsOfUtc, BidPx, AskPx, LastPx, VolumeTraded, Source)
    VALUES (src.InstrumentId, src.AsOfUtc, src.BidPx, src.AskPx, src.LastPx, src.VolumeTraded, 'SYNTHETIC');
GO

/* Ten calendar days per exchange, weekends flagged as non-trading. */
DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);

;WITH Days AS
(
    SELECT TOP (10)
        DayOffset = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
    FROM sys.all_objects
)
MERGE mkt.TradingCalendar AS tgt
USING
(
    SELECT
        e.ExchangeId,
        CalendarDate = DATEADD(DAY, -d.DayOffset, @Today),
        /* 1900-01-01 was a Monday, so %7 gives 5 = Saturday and 6 = Sunday regardless
           of the session's language setting (DATENAME would not). */
        IsTradingDay = CASE
            WHEN DATEDIFF(DAY, '19000101', DATEADD(DAY, -d.DayOffset, @Today)) % 7 IN (5, 6) THEN 0
            ELSE 1
        END
    FROM dbo.Exchange AS e
    CROSS JOIN Days AS d
) AS src
    ON tgt.ExchangeId = src.ExchangeId
   AND tgt.CalendarDate = src.CalendarDate
WHEN MATCHED THEN
    UPDATE SET tgt.IsTradingDay = src.IsTradingDay
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ExchangeId, CalendarDate, IsTradingDay)
    VALUES (src.ExchangeId, src.CalendarDate, src.IsTradingDay);
GO
