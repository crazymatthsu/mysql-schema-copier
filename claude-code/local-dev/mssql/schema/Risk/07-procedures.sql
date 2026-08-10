/*
    Risk - stored procedures.
*/

/*
    Pre-trade check called by Orders.dbo.usp_PlaceOrder.

    Reads limits locally, the current position from Trading, and the reference price
    from ReferenceData - three databases in one procedure, which is the dependency
    shape that has to survive the clone.
*/
CREATE OR ALTER PROCEDURE dbo.usp_CheckOrderRisk
    @AccountId    INT,
    @InstrumentId INT,
    @SideCode     VARCHAR(4),
    @OrderQty     DECIMAL(19, 4),
    @LimitPrice   DECIMAL(19, 6) = NULL,
    @ClOrdId      VARCHAR(36)    = NULL,
    @Decision     VARCHAR(8)     = NULL OUTPUT,
    @ReasonCode   VARCHAR(40)    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Decision = 'APPROVED';
    SET @ReasonCode = NULL;

    IF @SideCode NOT IN ('BUY', 'SELL')
        THROW 53001, 'usp_CheckOrderRisk: @SideCode must be BUY or SELL.', 1;

    /* Reference price: the order's own limit price when it has one, else last traded. */
    DECLARE @ReferencePx DECIMAL(19, 6) = @LimitPrice;

    IF @ReferencePx IS NULL
        SELECT @ReferencePx = lp.LastPx
        FROM ReferenceData.mkt.vw_LatestPrice AS lp
        WHERE lp.InstrumentId = @InstrumentId;

    DECLARE @Notional DECIMAL(19, 4) =
        CASE WHEN @ReferencePx IS NULL THEN NULL
             ELSE CAST(@OrderQty * @ReferencePx AS DECIMAL(19, 4))
        END;

    /* Instrument-specific limit wins over the account-wide default. */
    DECLARE @MaxOrderQty       DECIMAL(19, 4);
    DECLARE @MaxOrderNotional  DECIMAL(19, 4);
    DECLARE @MaxNetPositionQty DECIMAL(19, 4);

    SELECT TOP (1)
        @MaxOrderQty       = rl.MaxOrderQty,
        @MaxOrderNotional  = rl.MaxOrderNotional,
        @MaxNetPositionQty = rl.MaxNetPositionQty
    FROM dbo.RiskLimit AS rl
    WHERE rl.AccountId = @AccountId
      AND rl.IsActive = 1
      AND rl.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
      AND (rl.InstrumentId = @InstrumentId OR rl.InstrumentId IS NULL)
    ORDER BY CASE WHEN rl.InstrumentId IS NULL THEN 1 ELSE 0 END;

    IF @Decision = 'APPROVED' AND NOT EXISTS
    (
        SELECT 1
        FROM ReferenceData.dbo.Instrument AS i
        WHERE i.InstrumentId = @InstrumentId
          AND i.IsActive = 1
    )
    BEGIN
        SET @Decision = 'REJECTED';
        SET @ReasonCode = 'UNKNOWN_INSTRUMENT';
    END;

    IF @Decision = 'APPROVED' AND @MaxOrderQty IS NOT NULL AND @OrderQty > @MaxOrderQty
    BEGIN
        SET @Decision = 'REJECTED';
        SET @ReasonCode = 'MAX_ORDER_QTY';
    END;

    IF @Decision = 'APPROVED' AND @MaxOrderNotional IS NOT NULL
       AND @Notional IS NOT NULL AND @Notional > @MaxOrderNotional
    BEGIN
        SET @Decision = 'REJECTED';
        SET @ReasonCode = 'MAX_ORDER_NOTIONAL';
    END;

    IF @Decision = 'APPROVED' AND @MaxNetPositionQty IS NOT NULL
    BEGIN
        DECLARE @CurrentQty DECIMAL(19, 4) =
        (
            SELECT ISNULL(SUM(p.Quantity), 0)
            FROM Trading.dbo.Position AS p
            WHERE p.AccountId = @AccountId
              AND p.InstrumentId = @InstrumentId
        );

        DECLARE @ProjectedQty DECIMAL(19, 4) =
            @CurrentQty + CASE WHEN @SideCode = 'BUY' THEN @OrderQty ELSE -@OrderQty END;

        IF ABS(@ProjectedQty) > @MaxNetPositionQty
        BEGIN
            SET @Decision = 'REJECTED';
            SET @ReasonCode = 'MAX_NET_POSITION';
        END;
    END;

    INSERT dbo.RiskCheckLog
        (ClOrdId, AccountId, InstrumentId, SideCode, RequestedQty, ReferencePx, Notional, Decision, ReasonCode)
    VALUES
        (@ClOrdId, @AccountId, @InstrumentId, @SideCode, @OrderQty, @ReferencePx, @Notional, @Decision, @ReasonCode);
END;
GO

/*
    Account-level exposure summary - the local equivalent of EXEC Risk.dbo.CalculateRisk.
*/
CREATE OR ALTER PROCEDURE dbo.usp_CalculateRisk
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.AccountId,
        e.InstrumentId,
        e.Symbol,
        e.CurrencyCode,
        e.Quantity,
        e.AvgPrice,
        e.LastPx,
        e.GrossNotional,
        e.NetNotional,
        e.MaxNetPositionQty,
        e.LimitUtilisationPct
    FROM dbo.vw_AccountExposure AS e
    WHERE e.AccountId = @AccountId
      AND e.Quantity <> 0
    ORDER BY e.GrossNotional DESC;

    SELECT
        AccountId          = @AccountId,
        OpenPositions      = COUNT(*),
        GrossExposure      = ISNULL(SUM(e.GrossNotional), 0),
        NetExposure        = ISNULL(SUM(e.NetNotional), 0),
        WorstUtilisation   = MAX(e.LimitUtilisationPct)
    FROM dbo.vw_AccountExposure AS e
    WHERE e.AccountId = @AccountId
      AND e.Quantity <> 0;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SetRiskLimit
    @AccountId         INT,
    @InstrumentId      INT            = NULL,
    @MaxOrderQty       DECIMAL(19, 4) = NULL,
    @MaxOrderNotional  DECIMAL(19, 4) = NULL,
    @MaxNetPositionQty DECIMAL(19, 4) = NULL,
    @CurrencyCode      CHAR(3)        = 'USD'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @MaxOrderQty IS NULL AND @MaxOrderNotional IS NULL AND @MaxNetPositionQty IS NULL
        THROW 53002, 'usp_SetRiskLimit: at least one limit value is required.', 1;

    UPDATE dbo.RiskLimit
    SET MaxOrderQty       = @MaxOrderQty,
        MaxOrderNotional  = @MaxOrderNotional,
        MaxNetPositionQty = @MaxNetPositionQty,
        CurrencyCode      = @CurrencyCode,
        IsActive          = 1
    WHERE AccountId = @AccountId
      AND ((@InstrumentId IS NULL AND InstrumentId IS NULL) OR InstrumentId = @InstrumentId);

    IF @@ROWCOUNT = 0
        INSERT dbo.RiskLimit
            (AccountId, InstrumentId, MaxOrderQty, MaxOrderNotional, MaxNetPositionQty, CurrencyCode)
        VALUES
            (@AccountId, @InstrumentId, @MaxOrderQty, @MaxOrderNotional, @MaxNetPositionQty, @CurrencyCode);
END;
GO
