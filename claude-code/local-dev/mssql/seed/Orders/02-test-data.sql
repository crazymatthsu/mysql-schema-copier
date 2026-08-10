/*
    Orders - synthetic trading activity.

    The orders and fills are placed through dbo.usp_PlaceOrder and
    dbo.usp_RecordExecution rather than being INSERTed directly. That means seeding also
    exercises the cross-database chain end to end:

        Orders -> Risk (pre-trade check) -> Trading (position + cash) -> ReferenceData

    and the resulting positions in Trading are genuinely derived from the executions,
    the way they are upstream.

    Everything is deterministic: same seed run, same data. The whole block is skipped
    when SEED-00001 already exists, so `local-env seed` stays re-runnable.
*/

IF NOT EXISTS (SELECT 1 FROM dbo.[Order] AS o WHERE o.ClOrdId = 'SEED-00001')
BEGIN
    DECLARE @Universe TABLE
    (
        Rn           INT            NOT NULL PRIMARY KEY,
        InstrumentId INT            NOT NULL,
        LotSize      INT            NOT NULL,
        LastPx       DECIMAL(19, 6) NOT NULL
    );

    INSERT @Universe (Rn, InstrumentId, LotSize, LastPx)
    SELECT
        ROW_NUMBER() OVER (ORDER BY i.InstrumentId),
        i.InstrumentId,
        i.LotSize,
        ISNULL(lp.LastPx, 100.00)
    FROM ReferenceData.dbo.Instrument AS i
    LEFT JOIN ReferenceData.mkt.vw_LatestPrice AS lp
        ON lp.InstrumentId = i.InstrumentId
    WHERE i.IsActive = 1;

    DECLARE @UniverseCount INT = (SELECT COUNT(*) FROM @Universe);
    DECLARE @OrderCount    INT = 120;
    DECLARE @i             INT = 1;

    DECLARE @Rn            INT;
    DECLARE @InstrumentId  INT;
    DECLARE @LotSize       INT;
    DECLARE @LastPx        DECIMAL(19, 6);
    DECLARE @AccountId     INT;
    DECLARE @SideCode      VARCHAR(4);
    DECLARE @OrderTypeCode VARCHAR(10);
    DECLARE @TifCode       VARCHAR(3);
    DECLARE @Venue         VARCHAR(10);
    DECLARE @TargetNotional DECIMAL(19, 4);
    DECLARE @OrderQty      DECIMAL(19, 4);
    DECLARE @LimitPrice    DECIMAL(19, 6);
    DECLARE @ClOrdId       VARCHAR(36);
    DECLARE @ExecId1       VARCHAR(36);
    DECLARE @ExecId2       VARCHAR(36);
    DECLARE @OrderId       BIGINT;
    DECLARE @StatusCode    VARCHAR(20);
    DECLARE @RejectReason  VARCHAR(40);
    DECLARE @FillQty       DECIMAL(19, 4);
    DECLARE @FillQty2      DECIMAL(19, 4);
    DECLARE @FillPx2       DECIMAL(19, 6);
    DECLARE @NewStatus     VARCHAR(20);
    DECLARE @NewCumQty     DECIMAL(19, 4);

    WHILE @i <= @OrderCount
    BEGIN
        SET @Rn = ((@i - 1) % @UniverseCount) + 1;

        SELECT
            @InstrumentId = u.InstrumentId,
            @LotSize      = u.LotSize,
            @LastPx       = u.LastPx
        FROM @Universe AS u
        WHERE u.Rn = @Rn;

        SET @AccountId     = 1001 + (@i % 6);
        SET @SideCode      = CASE WHEN @i % 3 = 0 THEN 'SELL' ELSE 'BUY' END;
        SET @OrderTypeCode = CASE WHEN @i % 7 = 0 THEN 'MARKET' ELSE 'LIMIT' END;
        SET @TifCode       = CASE WHEN @i % 11 = 0 THEN 'IOC'
                                  WHEN @i % 5 = 0 THEN 'GTC'
                                  ELSE 'DAY' END;
        SET @Venue         = CASE @i % 3 WHEN 0 THEN 'PRIMARY' WHEN 1 THEN 'DARK1' ELSE 'ATS2' END;

        /* Size from a target notional so quantities stay sane across price levels. */
        SET @TargetNotional = 50000.0 * (1 + (@i % 5));
        SET @OrderQty = FLOOR(@TargetNotional / (@LastPx * @LotSize)) * @LotSize;

        IF @OrderQty < @LotSize
            SET @OrderQty = @LotSize;

        SET @LimitPrice = CASE
            WHEN @OrderTypeCode = 'MARKET' THEN NULL
            WHEN @SideCode = 'BUY' THEN CAST(@LastPx * 1.001 AS DECIMAL(19, 6))
            ELSE CAST(@LastPx * 0.999 AS DECIMAL(19, 6))
        END;

        SET @ClOrdId = 'SEED-' + RIGHT('00000' + CAST(@i AS VARCHAR(10)), 5);
        SET @ExecId1 = 'SEEDEX-' + RIGHT('00000' + CAST(@i AS VARCHAR(10)), 5) + '-1';
        SET @ExecId2 = 'SEEDEX-' + RIGHT('00000' + CAST(@i AS VARCHAR(10)), 5) + '-2';

        EXEC dbo.usp_PlaceOrder
            @ClOrdId       = @ClOrdId,
            @AccountId     = @AccountId,
            @InstrumentId  = @InstrumentId,
            @SideCode      = @SideCode,
            @OrderQty      = @OrderQty,
            @OrderTypeCode = @OrderTypeCode,
            @LimitPrice    = @LimitPrice,
            @TifCode       = @TifCode,
            @TraderId      = 1,
            @Venue         = @Venue,
            @OrderId       = @OrderId OUTPUT,
            @StatusCode    = @StatusCode OUTPUT,
            @RejectReason  = @RejectReason OUTPUT;

        IF @StatusCode = 'NEW'
        BEGIN
            /*
                Fill profile:
                  i % 4 = 1  fully filled in one execution
                  i % 4 = 2  half filled, still working
                  i % 4 = 3  fully filled across two executions
                  i % 4 = 0  left working, then cancelled every tenth order
            */
            IF @i % 4 = 1
            BEGIN
                EXEC dbo.usp_RecordExecution
                    @ExecId        = @ExecId1,
                    @LastQty       = @OrderQty,
                    @LastPx        = @LastPx,
                    @OrderId       = @OrderId,
                    @VenueExecId   = NULL,
                    @LiquidityFlag = 'R',
                    @Commission    = 0,
                    @NewStatusCode = @NewStatus OUTPUT,
                    @NewCumQty     = @NewCumQty OUTPUT;
            END
            ELSE IF @i % 4 = 2
            BEGIN
                SET @FillQty = FLOOR((@OrderQty / 2) / @LotSize) * @LotSize;
                IF @FillQty < @LotSize SET @FillQty = @LotSize;

                EXEC dbo.usp_RecordExecution
                    @ExecId        = @ExecId1,
                    @LastQty       = @FillQty,
                    @LastPx        = @LastPx,
                    @OrderId       = @OrderId,
                    @LiquidityFlag = 'A',
                    @Commission    = 0,
                    @NewStatusCode = @NewStatus OUTPUT,
                    @NewCumQty     = @NewCumQty OUTPUT;
            END
            ELSE IF @i % 4 = 3
            BEGIN
                SET @FillQty = FLOOR((@OrderQty / 2) / @LotSize) * @LotSize;
                IF @FillQty < @LotSize SET @FillQty = @LotSize;

                /* EXEC arguments must be variables or literals, never expressions. */
                SET @FillQty2 = @OrderQty - @FillQty;
                SET @FillPx2  = CAST(@LastPx * 1.0005 AS DECIMAL(19, 6));

                EXEC dbo.usp_RecordExecution
                    @ExecId        = @ExecId1,
                    @LastQty       = @FillQty,
                    @LastPx        = @LastPx,
                    @OrderId       = @OrderId,
                    @LiquidityFlag = 'A',
                    @Commission    = 0,
                    @NewStatusCode = @NewStatus OUTPUT,
                    @NewCumQty     = @NewCumQty OUTPUT;

                IF @FillQty2 > 0
                EXEC dbo.usp_RecordExecution
                    @ExecId        = @ExecId2,
                    @LastQty       = @FillQty2,
                    @LastPx        = @FillPx2,
                    @OrderId       = @OrderId,
                    @LiquidityFlag = 'R',
                    @Commission    = 0,
                    @NewStatusCode = @NewStatus OUTPUT,
                    @NewCumQty     = @NewCumQty OUTPUT;
            END
            ELSE IF @i % 10 = 0
            BEGIN
                EXEC dbo.usp_CancelOrder
                    @OrderId    = @OrderId,
                    @Reason     = 'CLIENT_CANCEL',
                    @StatusCode = @NewStatus OUTPUT;
            END;
        END;

        SET @i += 1;
    END;
END;
GO

/*
    Deliberate rejections, so the risk audit log has both outcomes in it and the
    integration tests have known-bad cases to assert against.
*/
DECLARE @JpInstrumentId INT =
(
    SELECT i.InstrumentId
    FROM ReferenceData.dbo.Instrument AS i
    INNER JOIN ReferenceData.dbo.Exchange AS e ON e.ExchangeId = i.ExchangeId
    WHERE i.Symbol = '7203' AND e.Mic = 'XTKS'
);

DECLARE @AaplId INT =
(
    SELECT i.InstrumentId
    FROM ReferenceData.dbo.Instrument AS i
    INNER JOIN ReferenceData.dbo.Exchange AS e ON e.ExchangeId = i.ExchangeId
    WHERE i.Symbol = 'AAPL' AND e.Mic = 'XNAS'
);

DECLARE @OrderId BIGINT, @StatusCode VARCHAR(20), @RejectReason VARCHAR(40);

/* Odd lot: 150 shares against a 100-share lot size. */
IF @JpInstrumentId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.[Order] WHERE ClOrdId = 'SEED-REJECT-ODDLOT')
    EXEC dbo.usp_PlaceOrder
        @ClOrdId       = 'SEED-REJECT-ODDLOT',
        @AccountId     = 1006,
        @InstrumentId  = @JpInstrumentId,
        @SideCode      = 'BUY',
        @OrderQty      = 150,
        @OrderTypeCode = 'MARKET',
        @OrderId       = @OrderId OUTPUT,
        @StatusCode    = @StatusCode OUTPUT,
        @RejectReason  = @RejectReason OUTPUT;

/* Over the instrument-level MaxOrderQty of 1000 that account 1002 has on AAPL. */
IF @AaplId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.[Order] WHERE ClOrdId = 'SEED-REJECT-MAXQTY')
    EXEC dbo.usp_PlaceOrder
        @ClOrdId       = 'SEED-REJECT-MAXQTY',
        @AccountId     = 1002,
        @InstrumentId  = @AaplId,
        @SideCode      = 'BUY',
        @OrderQty      = 5000,
        @OrderTypeCode = 'LIMIT',
        @LimitPrice    = 100.00,
        @OrderId       = @OrderId OUTPUT,
        @StatusCode    = @StatusCode OUTPUT,
        @RejectReason  = @RejectReason OUTPUT;
GO
