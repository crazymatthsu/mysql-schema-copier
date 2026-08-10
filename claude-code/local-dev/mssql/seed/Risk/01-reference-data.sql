/*
    Risk - limits.

    Every account gets a default, plus two deliberately tight instrument-level limits so
    the rejection paths in usp_CheckOrderRisk are reachable from seeded data alone.
*/

DECLARE @AccountId INT;

DECLARE AccountCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT a.AccountId FROM Trading.dbo.Account AS a WHERE a.IsActive = 1;

OPEN AccountCursor;
FETCH NEXT FROM AccountCursor INTO @AccountId;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.usp_SetRiskLimit
        @AccountId         = @AccountId,
        @InstrumentId      = NULL,
        @MaxOrderQty       = 50000,
        @MaxOrderNotional  = 5000000,
        @MaxNetPositionQty = 200000,
        @CurrencyCode      = 'USD';

    FETCH NEXT FROM AccountCursor INTO @AccountId;
END;

CLOSE AccountCursor;
DEALLOCATE AccountCursor;
GO

/* Tight per-instrument overrides used by the rejection tests. */
DECLARE @AaplId INT =
(
    SELECT i.InstrumentId
    FROM ReferenceData.dbo.Instrument AS i
    INNER JOIN ReferenceData.dbo.Exchange AS e ON e.ExchangeId = i.ExchangeId
    WHERE i.Symbol = 'AAPL' AND e.Mic = 'XNAS'
);

DECLARE @TslaId INT =
(
    SELECT i.InstrumentId
    FROM ReferenceData.dbo.Instrument AS i
    INNER JOIN ReferenceData.dbo.Exchange AS e ON e.ExchangeId = i.ExchangeId
    WHERE i.Symbol = 'TSLA' AND e.Mic = 'XNAS'
);

IF @AaplId IS NOT NULL
    EXEC dbo.usp_SetRiskLimit
        @AccountId         = 1002,
        @InstrumentId      = @AaplId,
        @MaxOrderQty       = 1000,
        @MaxOrderNotional  = 500000,
        @MaxNetPositionQty = 2500;

IF @TslaId IS NOT NULL
    EXEC dbo.usp_SetRiskLimit
        @AccountId         = 1005,
        @InstrumentId      = @TslaId,
        @MaxOrderQty       = 500,
        @MaxOrderNotional  = 250000,
        @MaxNetPositionQty = 1000;
GO
