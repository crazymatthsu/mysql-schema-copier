/*
    Validation - cross-database dependencies.

    This is the class of breakage a schema clone is most likely to hide: each database
    looks fine on its own, and only the three-part-name traffic between them fails.
*/

SELECT
    CheckName = N'Cross-database join ReferenceData x Trading returns rows',
    Detail    = CONCAT(N'rows=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ReferenceData.dbo.Instrument AS s
INNER JOIN Trading.dbo.Position AS p
    ON s.InstrumentId = p.InstrumentId;

SELECT
    CheckName = N'Trading.dbo.vw_PositionValuation resolves prices from ReferenceData',
    Detail    = CONCAT(N'valued=', SUM(CASE WHEN v.LastPx IS NOT NULL THEN 1 ELSE 0 END),
                       N' of ', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) > 0
                      AND SUM(CASE WHEN v.LastPx IS NOT NULL THEN 1 ELSE 0 END) = COUNT(*)
                     THEN 1 ELSE 0 END
FROM Trading.dbo.vw_PositionValuation AS v;

SELECT
    CheckName = N'Risk.dbo.vw_AccountExposure reads Trading and ReferenceData',
    Detail    = CONCAT(N'rows=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM Risk.dbo.vw_AccountExposure AS e
WHERE e.Quantity <> 0;

SELECT
    CheckName = N'Orders.dbo.vw_ExecutionEnriched joins Orders, ReferenceData and Trading',
    Detail    = CONCAT(N'rows=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM Orders.dbo.vw_ExecutionEnriched AS x;

/*
    Procedure smoke tests. These emit their own result sets, which the runner ignores
    because they do not carry the (CheckName, Detail, Passed) contract.
*/
DECLARE @Passed BIT = 1;
DECLARE @Detail NVARCHAR(400) = NULL;

BEGIN TRY
    EXEC Risk.dbo.usp_CalculateRisk @AccountId = 1001;
END TRY
BEGIN CATCH
    SET @Passed = 0;
    SET @Detail = ERROR_MESSAGE();
END CATCH;

SELECT
    CheckName = N'EXEC Risk.dbo.usp_CalculateRisk succeeds',
    Detail    = @Detail,
    Passed    = @Passed;

SET @Passed = 1;
SET @Detail = NULL;

BEGIN TRY
    EXEC Orders.dbo.usp_GetOrderBlotter @AccountId = 1001;
END TRY
BEGIN CATCH
    SET @Passed = 0;
    SET @Detail = ERROR_MESSAGE();
END CATCH;

SELECT
    CheckName = N'EXEC Orders.dbo.usp_GetOrderBlotter succeeds',
    Detail    = @Detail,
    Passed    = @Passed;

SET @Passed = 1;
SET @Detail = NULL;

BEGIN TRY
    EXEC ReferenceData.dbo.usp_GetInstrument @Symbol = 'AAPL', @Mic = 'XNAS';
END TRY
BEGIN CATCH
    SET @Passed = 0;
    SET @Detail = ERROR_MESSAGE();
END CATCH;

SELECT
    CheckName = N'EXEC ReferenceData.dbo.usp_GetInstrument succeeds',
    Detail    = @Detail,
    Passed    = @Passed;

/* The scalar function is called by Orders.usp_PlaceOrder across databases. */
SELECT
    CheckName = N'ReferenceData.dbo.ufn_RoundToTick snaps to the tick grid',
    Detail    = CONCAT(N'232.507 -> ', ReferenceData.dbo.ufn_RoundToTick(232.507, 0.01)),
    Passed    = CASE WHEN ReferenceData.dbo.ufn_RoundToTick(232.507, 0.01) = 232.510000 THEN 1 ELSE 0 END;
