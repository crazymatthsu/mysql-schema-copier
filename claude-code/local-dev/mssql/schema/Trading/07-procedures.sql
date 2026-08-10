/*
    Trading - stored procedures.
*/

/*
    The only supported way to mutate a position.

    Called by Orders.dbo.usp_RecordExecution across databases, which means the caller's
    login needs EXECUTE here as well: cross-database ownership chaining is off by
    default, so permissions do not follow the call. That is why every application login
    is mapped into every database it touches (see databases.yaml).
*/
CREATE OR ALTER PROCEDURE dbo.usp_ApplyExecution
    @AccountId    INT,
    @InstrumentId INT,
    @SideCode     VARCHAR(4),
    @LastQty      DECIMAL(19, 4),
    @LastPx       DECIMAL(19, 6),
    @ExecId       VARCHAR(36)    = NULL,
    @NewQuantity  DECIMAL(19, 4) = NULL OUTPUT,
    @RealizedPnL  DECIMAL(19, 4) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SideCode NOT IN ('BUY', 'SELL')
        THROW 52001, 'usp_ApplyExecution: @SideCode must be BUY or SELL.', 1;

    IF @LastQty IS NULL OR @LastQty <= 0
        THROW 52002, 'usp_ApplyExecution: @LastQty must be greater than zero.', 1;

    IF @LastPx IS NULL OR @LastPx <= 0
        THROW 52003, 'usp_ApplyExecution: @LastPx must be greater than zero.', 1;

    /* Cross-database validation standing in for the foreign key SQL Server cannot enforce. */
    DECLARE @CurrencyCode CHAR(3);

    SELECT @CurrencyCode = i.CurrencyCode
    FROM ReferenceData.dbo.Instrument AS i
    WHERE i.InstrumentId = @InstrumentId
      AND i.IsActive = 1;

    IF @CurrencyCode IS NULL
        THROW 52004, 'usp_ApplyExecution: unknown or inactive InstrumentId in ReferenceData.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Account AS a WHERE a.AccountId = @AccountId AND a.IsActive = 1)
        THROW 52005, 'usp_ApplyExecution: unknown or inactive AccountId.', 1;

    DECLARE @OwnsTransaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    IF @OwnsTransaction = 1
        BEGIN TRANSACTION;

    DECLARE @SignedQty DECIMAL(19, 4) = CASE WHEN @SideCode = 'BUY' THEN @LastQty ELSE -@LastQty END;
    DECLARE @Qty      DECIMAL(19, 4);
    DECLARE @Avg      DECIMAL(19, 6);
    DECLARE @Realized DECIMAL(19, 4);

    SELECT
        @Qty      = p.Quantity,
        @Avg      = p.AvgPrice,
        @Realized = p.RealizedPnL
    FROM dbo.Position AS p WITH (UPDLOCK, HOLDLOCK)
    WHERE p.AccountId = @AccountId
      AND p.InstrumentId = @InstrumentId;

    IF @Qty IS NULL
    BEGIN
        SET @Qty = 0;
        SET @Avg = 0;
        SET @Realized = 0;

        INSERT dbo.Position (AccountId, InstrumentId, Quantity, AvgPrice, RealizedPnL)
        VALUES (@AccountId, @InstrumentId, 0, 0, 0);
    END;

    DECLARE @NewQty        DECIMAL(19, 4) = @Qty + @SignedQty;
    DECLARE @NewAvg        DECIMAL(19, 6) = @Avg;
    DECLARE @RealizedDelta DECIMAL(19, 4) = 0;
    DECLARE @ClosedQty     DECIMAL(19, 4);

    IF @Qty = 0
    BEGIN
        /* Opening a new long or short leg. */
        SET @NewAvg = @LastPx;
    END
    ELSE IF SIGN(@Qty) = SIGN(@SignedQty)
    BEGIN
        /* Adding to the existing leg: weighted average cost. */
        SET @NewAvg = CAST(
            (ABS(@Qty) * @Avg + ABS(@SignedQty) * @LastPx) / (ABS(@Qty) + ABS(@SignedQty))
            AS DECIMAL(19, 6));
    END
    ELSE
    BEGIN
        /* Reducing, closing, or flipping: realise P&L on the closed quantity. */
        SET @ClosedQty = CASE WHEN ABS(@SignedQty) < ABS(@Qty) THEN ABS(@SignedQty) ELSE ABS(@Qty) END;
        SET @RealizedDelta = CAST(@ClosedQty * (@LastPx - @Avg) * SIGN(@Qty) AS DECIMAL(19, 4));

        IF @NewQty = 0
            SET @NewAvg = 0;
        ELSE IF SIGN(@NewQty) <> SIGN(@Qty)
            SET @NewAvg = @LastPx;      /* flipped through zero: the remainder is a new leg */
    END;

    UPDATE dbo.Position
    SET Quantity     = @NewQty,
        AvgPrice     = @NewAvg,
        RealizedPnL  = RealizedPnL + @RealizedDelta,
        LastExecId   = ISNULL(@ExecId, LastExecId),
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE AccountId = @AccountId
      AND InstrumentId = @InstrumentId;

    /* Buying consumes cash, selling releases it. */
    DECLARE @CashDelta DECIMAL(19, 4) = CAST(-1 * @SignedQty * @LastPx AS DECIMAL(19, 4));

    MERGE dbo.CashBalance WITH (HOLDLOCK) AS tgt
    USING
    (
        SELECT
            AccountId    = @AccountId,
            CurrencyCode = @CurrencyCode
    ) AS src
        ON tgt.AccountId = src.AccountId
       AND tgt.CurrencyCode = src.CurrencyCode
    WHEN MATCHED THEN
        UPDATE SET
            tgt.Amount       = tgt.Amount + @CashDelta,
            tgt.UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (AccountId, CurrencyCode, Amount)
        VALUES (@AccountId, @CurrencyCode, @CashDelta);

    SET @NewQuantity = @NewQty;
    SET @RealizedPnL = @Realized + @RealizedDelta;

    IF @OwnsTransaction = 1
        COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetAccountPositions
    @AccountId       INT,
    @IncludeFlat     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        v.AccountId,
        v.AccountCode,
        v.InstrumentId,
        v.Symbol,
        v.CurrencyCode,
        v.Quantity,
        v.AvgPrice,
        v.LastPx,
        v.MarketValue,
        v.UnrealizedPnL,
        v.RealizedPnL,
        v.UpdatedAtUtc
    FROM dbo.vw_PositionValuation AS v
    WHERE v.AccountId = @AccountId
      AND (@IncludeFlat = 1 OR v.Quantity <> 0)
    ORDER BY v.Symbol;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdjustCash
    @AccountId    INT,
    @CurrencyCode CHAR(3),
    @Amount       DECIMAL(19, 4)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Account WHERE AccountId = @AccountId)
        THROW 52006, 'usp_AdjustCash: unknown AccountId.', 1;

    MERGE dbo.CashBalance WITH (HOLDLOCK) AS tgt
    USING
    (
        SELECT
            AccountId    = @AccountId,
            CurrencyCode = @CurrencyCode
    ) AS src
        ON tgt.AccountId = src.AccountId
       AND tgt.CurrencyCode = src.CurrencyCode
    WHEN MATCHED THEN
        UPDATE SET
            tgt.Amount       = tgt.Amount + @Amount,
            tgt.UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (AccountId, CurrencyCode, Amount)
        VALUES (@AccountId, @CurrencyCode, @Amount);
END;
GO
