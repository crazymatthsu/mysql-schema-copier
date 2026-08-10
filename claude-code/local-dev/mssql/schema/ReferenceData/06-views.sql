/*
    ReferenceData - views.
*/

CREATE OR ALTER VIEW dbo.vw_ActiveInstrument
AS
SELECT
    i.InstrumentId,
    i.Symbol,
    i.Isin,
    i.InstrumentName,
    i.InstrumentType,
    i.SectorCode,
    i.LotSize,
    i.TickSize,
    i.CurrencyCode,
    c.CurrencyName,
    e.ExchangeId,
    e.Mic,
    e.ExchangeName,
    e.CountryCode,
    e.TimeZoneName
FROM dbo.Instrument AS i
INNER JOIN dbo.Exchange AS e
    ON e.ExchangeId = i.ExchangeId
INNER JOIN dbo.Currency AS c
    ON c.CurrencyCode = i.CurrencyCode
WHERE i.IsActive = 1
  AND e.IsActive = 1;
GO

/*
    Latest snapshot per instrument. OUTER APPLY keeps the plan shape close to the
    enterprise view, which reads from a much larger tick history.
*/
CREATE OR ALTER VIEW mkt.vw_LatestPrice
AS
SELECT
    i.InstrumentId,
    i.Symbol,
    i.CurrencyCode,
    p.AsOfUtc,
    p.BidPx,
    p.AskPx,
    p.LastPx,
    p.VolumeTraded
FROM dbo.Instrument AS i
OUTER APPLY
(
    SELECT TOP (1)
        s.AsOfUtc,
        s.BidPx,
        s.AskPx,
        s.LastPx,
        s.VolumeTraded
    FROM mkt.PriceSnapshot AS s
    WHERE s.InstrumentId = i.InstrumentId
    ORDER BY s.AsOfUtc DESC
) AS p;
GO
