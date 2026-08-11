/*
    Orders - stored procedures.

    This is where the cross-database dependency chain lives:

        Orders.usp_PlaceOrder      -> Risk.usp_CheckOrderRisk -> Trading, ReferenceData
        Orders.usp_RecordExecution -> Trading.usp_ApplyExecution

    Each hop needs the caller's login to be mapped, with EXECUTE, in the target
    database - cross-database ownership chaining is off by default.
*/

CREATE OR ALTER PROCEDURE dbo.usp_PlaceOrder
    @ClOrdId       VARCHAR(36),
    @AccountId     INT,
    @InstrumentId  INT,
    @SideCode      VARCHAR(4),
    @OrderQty      DECIMAL(19, 4),
    @OrderTypeCode VARCHAR(10)    = 'LIMIT',
    @LimitPrice    DECIMAL(19, 6) = NULL,
    @StopPrice     DECIMAL(19, 6) = NULL,
    @TifCode       VARCHAR(3)     = 'DAY',
    @TraderId      INT            = NULL,
    @Venue         VARCHAR(10)    = NULL,
    @ParentOrderId BIGINT         = NULL,
    @OrderId       BIGINT         = NULL OUTPUT,
    @StatusCode    VARCHAR(20)    = NULL OUTPUT,
    @RejectReason  VARCHAR(40)    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @OrderId = NULL;
    SET @StatusCode = NULL;
    SET @RejectReason = NULL;

    IF EXISTS (SELECT 1 FROM dbo.[Order] AS o WHERE o.ClOrdId = @ClOrdId)
        THROW 54001, 'usp_PlaceOrder: duplicate ClOrdId.', 1;

    IF @SideCode NOT IN ('BUY', 'SELL')
        THROW 54002, 'usp_PlaceOrder: @SideCode must be BUY or SELL.', 1;

    IF @OrderQty IS NULL OR @OrderQty <= 0
        THROW 54003, 'usp_PlaceOrder: @OrderQty must be greater than zero.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.OrderType AS t WHERE t.OrderTypeCode = @OrderTypeCode)
        THROW 54004, 'usp_PlaceOrder: unknown @OrderTypeCode.', 1;

    /* Instrument conventions live in ReferenceData, so read them across databases. */
    DECLARE @LotSize  INT;
    DECLARE @TickSize DECIMAL(19, 6);

    SELECT
        @LotSize  = i.LotSize,
        @TickSize = i.TickSize
    FROM ReferenceData.dbo.Instrument AS i
    WHERE i.InstrumentId = @InstrumentId
      AND i.IsActive = 1;

    IF @LotSize IS NULL
        THROW 54005, 'usp_PlaceOrder: unknown or inactive InstrumentId in ReferenceData.', 1;

    IF NOT EXISTS (SELECT 1 FROM Trading.dbo.Account AS a WHERE a.AccountId = @AccountId AND a.IsActive = 1)
        THROW 54006, 'usp_PlaceOrder: unknown or inactive AccountId in Trading.', 1;

    DECLARE @RequiresLimit BIT, @RequiresStop BIT;

    SELECT
        @RequiresLimit = t.RequiresLimit,
        @RequiresStop  = t.RequiresStop
    FROM dbo.OrderType AS t
    WHERE t.OrderTypeCode = @OrderTypeCode;

    IF @RequiresLimit = 1 AND @LimitPrice IS NULL
        THROW 54007, 'usp_PlaceOrder: this order type requires @LimitPrice.', 1;

    IF @RequiresStop = 1 AND @StopPrice IS NULL
        THROW 54008, 'usp_PlaceOrder: this order type requires @StopPrice.', 1;

    /* Snap prices to the instrument tick using the ReferenceData function. */
    IF @LimitPrice IS NOT NULL
        SET @LimitPrice = ReferenceData.dbo.ufn_RoundToTick(@LimitPrice, @TickSize);

    IF @StopPrice IS NOT NULL
        SET @StopPrice = ReferenceData.dbo.ufn_RoundToTick(@StopPrice, @TickSize);

    DECLARE @Decision   VARCHAR(8);
    DECLARE @ReasonCode VARCHAR(40);

    /* Lot check without the modulo operator: @OrderQty is DECIMAL, and % is only
       reliable over integer types. */
    IF @OrderQty <> FLOOR(@OrderQty / @LotSize) * @LotSize
    BEGIN
        SET @Decision = 'REJECTED';
        SET @ReasonCode = 'ODD_LOT';
    END
    ELSE
    BEGIN
        /*
            Pre-trade risk. Called outside the order transaction on purpose: the risk
            log is an audit record and must survive a rolled-back order insert.
        */
        EXEC Risk.dbo.usp_CheckOrderRisk
            @AccountId    = @AccountId,
            @InstrumentId = @InstrumentId,
            @SideCode     = @SideCode,
            @OrderQty     = @OrderQty,
            @LimitPrice   = @LimitPrice,
            @ClOrdId      = @ClOrdId,
            @Decision     = @Decision OUTPUT,
            @ReasonCode   = @ReasonCode OUTPUT;
    END;

    DECLARE @Inserted TABLE (OrderId BIGINT NOT NULL);

    BEGIN TRANSACTION;

    INSERT dbo.[Order]
        (ClOrdId, ParentOrderId, AccountId, InstrumentId, TraderId, SideCode, OrderTypeCode,
         TifCode, StatusCode, OrderQty, LimitPrice, StopPrice, LeavesQty, CumQty, AvgPx,
         Venue, RejectReason)
    OUTPUT inserted.OrderId INTO @Inserted (OrderId)
    VALUES
        (@ClOrdId, @ParentOrderId, @AccountId, @InstrumentId, @TraderId, @SideCode, @OrderTypeCode,
         @TifCode,
         CASE WHEN @Decision = 'REJECTED' THEN 'REJECTED' ELSE 'NEW' END,
         @OrderQty, @LimitPrice, @StopPrice,
         CASE WHEN @Decision = 'REJECTED' THEN 0 ELSE @OrderQty END,
         0, 0, @Venue,
         CASE WHEN @Decision = 'REJECTED' THEN @ReasonCode END);

    SELECT @OrderId = MAX(OrderId) FROM @Inserted;

    COMMIT TRANSACTION;

    SET @StatusCode = CASE WHEN @Decision = 'REJECTED' THEN 'REJECTED' ELSE 'NEW' END;
    SET @RejectReason = CASE WHEN @Decision = 'REJECTED' THEN @ReasonCode END;
END;
GO

/*
    Records a fill, moves the order along, and pushes the position change into Trading.
    All three happen in one transaction: a fill that does not reach the position book
    is worse than a rejected order.
*/
CREATE OR ALTER PROCEDURE dbo.usp_RecordExecution
    @ExecId         VARCHAR(36),
    @LastQty        DECIMAL(19, 4),
    @LastPx         DECIMAL(19, 6),
    @OrderId        BIGINT         = NULL,
    @ClOrdId        VARCHAR(36)    = NULL,
    @VenueExecId    VARCHAR(40)    = NULL,
    @LiquidityFlag  CHAR(1)        = NULL,
    @Commission     DECIMAL(19, 4) = 0,
    @TradeDate      DATE           = NULL,
    @NewStatusCode  VARCHAR(20)    = NULL OUTPUT,
    @NewCumQty      DECIMAL(19, 4) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @OrderId IS NULL AND @ClOrdId IS NULL
        THROW 54010, 'usp_RecordExecution: supply @OrderId or @ClOrdId.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Execution AS x WHERE x.ExecId = @ExecId)
        THROW 54011, 'usp_RecordExecution: duplicate ExecId.', 1;

    SET @TradeDate = ISNULL(@TradeDate, CAST(SYSUTCDATETIME() AS DATE));

    /* Resolve the key first: assigning @OrderId in the same SELECT that filters on it
       would make the predicate depend on the row order. */
    IF @OrderId IS NULL
        SELECT @OrderId = o.OrderId
        FROM dbo.[Order] AS o
        WHERE o.ClOrdId = @ClOrdId;

    IF @OrderId IS NULL
        THROW 54012, 'usp_RecordExecution: order not found.', 1;

    BEGIN TRANSACTION;

    DECLARE @AccountId    INT;
    DECLARE @InstrumentId INT;
    DECLARE @SideCode     VARCHAR(4);
    DECLARE @OrderQty     DECIMAL(19, 4);
    DECLARE @CumQty       DECIMAL(19, 4);
    DECLARE @LeavesQty    DECIMAL(19, 4);
    DECLARE @AvgPx        DECIMAL(19, 6);
    DECLARE @StatusCode   VARCHAR(20);

    SELECT
        @AccountId    = o.AccountId,
        @InstrumentId = o.InstrumentId,
        @SideCode     = o.SideCode,
        @OrderQty     = o.OrderQty,
        @CumQty       = o.CumQty,
        @LeavesQty    = o.LeavesQty,
        @AvgPx        = o.AvgPx,
        @StatusCode   = o.StatusCode
    FROM dbo.[Order] AS o WITH (UPDLOCK, ROWLOCK)
    WHERE o.OrderId = @OrderId;

    IF @AccountId IS NULL
        THROW 54012, 'usp_RecordExecution: order not found.', 1;

    IF @StatusCode IN ('FILLED', 'CANCELED', 'REJECTED', 'EXPIRED')
        THROW 54013, 'usp_RecordExecution: order is in a terminal state.', 1;

    IF @LastQty > @LeavesQty
        THROW 54014, 'usp_RecordExecution: fill quantity exceeds leaves quantity.', 1;

    INSERT dbo.Execution
        (ExecId, OrderId, ExecType, LastQty, LastPx, TradeDate, SettlementDate,
         VenueExecId, LiquidityFlag, Commission)
    VALUES
        (@ExecId, @OrderId, 'TRADE', @LastQty, @LastPx, @TradeDate, DATEADD(DAY, 2, @TradeDate),
         @VenueExecId, @LiquidityFlag, @Commission);

    DECLARE @NewCum DECIMAL(19, 4) = @CumQty + @LastQty;
    DECLARE @NewAvg DECIMAL(19, 6) =
        CAST((@CumQty * @AvgPx + @LastQty * @LastPx) / @NewCum AS DECIMAL(19, 6));
    DECLARE @NewLeaves DECIMAL(19, 4) = @LeavesQty - @LastQty;
    DECLARE @NewStatus VARCHAR(20) =
        CASE WHEN @NewLeaves = 0 THEN 'FILLED' ELSE 'PARTIALLY_FILLED' END;

    UPDATE dbo.[Order]
    SET CumQty       = @NewCum,
        LeavesQty    = @NewLeaves,
        AvgPx        = @NewAvg,
        StatusCode   = @NewStatus,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE OrderId = @OrderId;

    /* Cross-database: the position book lives in Trading. */
    EXEC Trading.dbo.usp_ApplyExecution
        @AccountId    = @AccountId,
        @InstrumentId = @InstrumentId,
        @SideCode     = @SideCode,
        @LastQty      = @LastQty,
        @LastPx       = @LastPx,
        @ExecId       = @ExecId;

    COMMIT TRANSACTION;

    SET @NewStatusCode = @NewStatus;
    SET @NewCumQty = @NewCum;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CancelOrder
    @OrderId    BIGINT      = NULL,
    @ClOrdId    VARCHAR(36) = NULL,
    @Reason     VARCHAR(40) = 'CLIENT_CANCEL',
    @StatusCode VARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @OrderId IS NULL AND @ClOrdId IS NULL
        THROW 54020, 'usp_CancelOrder: supply @OrderId or @ClOrdId.', 1;

    IF @OrderId IS NULL
        SELECT @OrderId = o.OrderId
        FROM dbo.[Order] AS o
        WHERE o.ClOrdId = @ClOrdId;

    IF @OrderId IS NULL
        THROW 54021, 'usp_CancelOrder: order not found.', 1;

    BEGIN TRANSACTION;

    DECLARE @CurrentStatus VARCHAR(20);

    SELECT @CurrentStatus = o.StatusCode
    FROM dbo.[Order] AS o WITH (UPDLOCK, ROWLOCK)
    WHERE o.OrderId = @OrderId;

    IF @CurrentStatus IS NULL
        THROW 54021, 'usp_CancelOrder: order not found.', 1;

    IF @CurrentStatus IN ('FILLED', 'CANCELED', 'REJECTED', 'EXPIRED')
        THROW 54022, 'usp_CancelOrder: order is already in a terminal state.', 1;

    UPDATE dbo.[Order]
    SET StatusCode   = 'CANCELED',
        LeavesQty    = 0,
        RejectReason = @Reason,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE OrderId = @OrderId;

    COMMIT TRANSACTION;

    SET @StatusCode = 'CANCELED';
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetOrderBlotter
    @AccountId  INT         = NULL,
    @TradeDate  DATE        = NULL,
    @StatusCode VARCHAR(20) = NULL,
    @Symbol     VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.ClOrdId,
        o.AccountId,
        a.AccountCode,
        i.Symbol,
        i.CurrencyCode,
        o.SideCode,
        o.OrderTypeCode,
        o.TifCode,
        o.StatusCode,
        o.OrderQty,
        o.LimitPrice,
        o.CumQty,
        o.LeavesQty,
        o.AvgPx,
        o.Venue,
        o.RejectReason,
        o.CreatedAtUtc
    FROM dbo.[Order] AS o
    INNER JOIN ReferenceData.dbo.Instrument AS i
        ON i.InstrumentId = o.InstrumentId
    INNER JOIN Trading.dbo.Account AS a
        ON a.AccountId = o.AccountId
    WHERE (@AccountId IS NULL OR o.AccountId = @AccountId)
      AND (@StatusCode IS NULL OR o.StatusCode = @StatusCode)
      AND (@Symbol IS NULL OR i.Symbol = @Symbol)
      AND (@TradeDate IS NULL OR CAST(o.CreatedAtUtc AS DATE) = @TradeDate)
    ORDER BY o.CreatedAtUtc DESC, o.OrderId DESC;
END;
GO
