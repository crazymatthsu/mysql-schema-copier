/*
    Risk - views.

    Reads Trading and ReferenceData by three-part name: Risk owns no position data of
    its own. This view is the reason Risk must be provisioned after Trading.
*/

CREATE OR ALTER VIEW dbo.vw_AccountExposure
AS
SELECT
    p.AccountId,
    p.InstrumentId,
    i.Symbol,
    i.CurrencyCode,
    p.Quantity,
    p.AvgPrice,
    lp.LastPx,
    GrossNotional = CAST(ABS(p.Quantity) * ISNULL(lp.LastPx, p.AvgPrice) AS DECIMAL(19, 4)),
    NetNotional   = CAST(p.Quantity * ISNULL(lp.LastPx, p.AvgPrice) AS DECIMAL(19, 4)),
    l.MaxNetPositionQty,
    LimitUtilisationPct = CASE
        WHEN l.MaxNetPositionQty IS NULL OR l.MaxNetPositionQty = 0 THEN NULL
        ELSE CAST(100.0 * ABS(p.Quantity) / l.MaxNetPositionQty AS DECIMAL(9, 2))
    END
FROM Trading.dbo.Position AS p
INNER JOIN ReferenceData.dbo.Instrument AS i
    ON i.InstrumentId = p.InstrumentId
LEFT JOIN ReferenceData.mkt.vw_LatestPrice AS lp
    ON lp.InstrumentId = p.InstrumentId
OUTER APPLY
(
    SELECT TOP (1)
        rl.MaxNetPositionQty
    FROM dbo.RiskLimit AS rl
    WHERE rl.AccountId = p.AccountId
      AND rl.IsActive = 1
      AND (rl.InstrumentId = p.InstrumentId OR rl.InstrumentId IS NULL)
    ORDER BY CASE WHEN rl.InstrumentId IS NULL THEN 1 ELSE 0 END
) AS l;
GO
