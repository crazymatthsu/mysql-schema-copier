/*
    Trading - views.

    vw_PositionValuation is a three-part-name view: it reads ReferenceData from inside
    Trading. Keeping the local database names identical to the enterprise ones is what
    makes this work unchanged - see docs/mssql-podman-schema-cloning.md section 8.
*/

CREATE OR ALTER VIEW dbo.vw_PositionValuation
AS
SELECT
    p.AccountId,
    a.AccountCode,
    a.AccountName,
    p.InstrumentId,
    i.Symbol,
    i.InstrumentName,
    i.CurrencyCode,
    p.Quantity,
    p.AvgPrice,
    lp.LastPx,
    lp.AsOfUtc AS PriceAsOfUtc,
    MarketValue   = CAST(p.Quantity * ISNULL(lp.LastPx, p.AvgPrice) AS DECIMAL(19, 4)),
    UnrealizedPnL = CAST(p.Quantity * (ISNULL(lp.LastPx, p.AvgPrice) - p.AvgPrice) AS DECIMAL(19, 4)),
    p.RealizedPnL,
    p.UpdatedAtUtc
FROM dbo.Position AS p
INNER JOIN dbo.Account AS a
    ON a.AccountId = p.AccountId
INNER JOIN ReferenceData.dbo.Instrument AS i
    ON i.InstrumentId = p.InstrumentId
LEFT JOIN ReferenceData.mkt.vw_LatestPrice AS lp
    ON lp.InstrumentId = p.InstrumentId;
GO

CREATE OR ALTER VIEW dbo.vw_AccountSummary
AS
SELECT
    a.AccountId,
    a.AccountCode,
    a.AccountName,
    a.BaseCurrency,
    OpenPositions = COUNT(CASE WHEN p.Quantity <> 0 THEN 1 END),
    GrossQuantity = ISNULL(SUM(ABS(p.Quantity)), 0),
    RealizedPnL   = ISNULL(SUM(p.RealizedPnL), 0),
    CashAmount    = ISNULL(MAX(cb.Amount), 0)
FROM dbo.Account AS a
LEFT JOIN dbo.Position AS p
    ON p.AccountId = a.AccountId
LEFT JOIN dbo.CashBalance AS cb
    ON cb.AccountId = a.AccountId
   AND cb.CurrencyCode = a.BaseCurrency
GROUP BY
    a.AccountId,
    a.AccountCode,
    a.AccountName,
    a.BaseCurrency;
GO
