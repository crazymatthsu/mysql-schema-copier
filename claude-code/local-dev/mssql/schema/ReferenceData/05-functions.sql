/*
    ReferenceData - functions.
*/

CREATE OR ALTER FUNCTION dbo.ufn_RoundToTick
(
    @Price    DECIMAL(19, 6),
    @TickSize DECIMAL(19, 6)
)
RETURNS DECIMAL(19, 6)
WITH SCHEMABINDING
AS
BEGIN
    IF @Price IS NULL OR @TickSize IS NULL OR @TickSize <= 0
        RETURN @Price;

    RETURN CAST(ROUND(@Price / @TickSize, 0) AS DECIMAL(19, 6)) * @TickSize;
END;
GO

/*
    Inline table-valued function - the shape the order-management service uses to
    resolve a venue's tradable universe.
*/
CREATE OR ALTER FUNCTION dbo.tvf_InstrumentsByExchange
(
    @Mic CHAR(4)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        i.InstrumentId,
        i.Symbol,
        i.InstrumentName,
        i.InstrumentType,
        i.CurrencyCode,
        i.LotSize,
        i.TickSize
    FROM dbo.Instrument AS i
    INNER JOIN dbo.Exchange AS e
        ON e.ExchangeId = i.ExchangeId
    WHERE e.Mic = @Mic
      AND i.IsActive = 1
);
GO
