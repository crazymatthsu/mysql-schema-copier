/*
    Risk - tables.

    Limits are held per account, optionally narrowed to a single instrument. Every
    pre-trade check is logged, which is what the compliance extract reads.
*/

IF OBJECT_ID(N'dbo.RiskLimit', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RiskLimit
    (
        LimitId            INT             NOT NULL IDENTITY(1, 1),
        AccountId          INT             NOT NULL,  -- Trading.dbo.Account (cross-database)
        InstrumentId       INT             NULL,      -- NULL = account-wide default
        MaxOrderQty        DECIMAL(19, 4)  NULL,
        MaxOrderNotional   DECIMAL(19, 4)  NULL,
        MaxNetPositionQty  DECIMAL(19, 4)  NULL,
        CurrencyCode       CHAR(3)         NOT NULL CONSTRAINT DF_RiskLimit_CurrencyCode DEFAULT ('USD'),
        IsActive           BIT             NOT NULL CONSTRAINT DF_RiskLimit_IsActive DEFAULT (1),
        EffectiveFrom      DATE            NOT NULL CONSTRAINT DF_RiskLimit_EffectiveFrom DEFAULT (CAST(SYSUTCDATETIME() AS DATE)),
        CONSTRAINT PK_RiskLimit PRIMARY KEY CLUSTERED (LimitId),
        CONSTRAINT CK_RiskLimit_AnyLimit CHECK
        (
            MaxOrderQty IS NOT NULL
            OR MaxOrderNotional IS NOT NULL
            OR MaxNetPositionQty IS NOT NULL
        )
    );
END;
GO

IF OBJECT_ID(N'dbo.RiskCheckLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RiskCheckLog
    (
        CheckId       BIGINT          NOT NULL IDENTITY(1, 1),
        ClOrdId       VARCHAR(36)     NULL,
        AccountId     INT             NOT NULL,
        InstrumentId  INT             NOT NULL,
        SideCode      VARCHAR(4)      NOT NULL,
        RequestedQty  DECIMAL(19, 4)  NOT NULL,
        ReferencePx   DECIMAL(19, 6)  NULL,
        Notional      DECIMAL(19, 4)  NULL,
        Decision      VARCHAR(8)      NOT NULL,
        ReasonCode    VARCHAR(40)     NULL,
        CheckedAtUtc  DATETIME2(3)    NOT NULL CONSTRAINT DF_RiskCheckLog_CheckedAtUtc DEFAULT (SYSUTCDATETIME()),
        CheckedBy     SYSNAME         NOT NULL CONSTRAINT DF_RiskCheckLog_CheckedBy DEFAULT (SUSER_SNAME()),
        CONSTRAINT PK_RiskCheckLog PRIMARY KEY CLUSTERED (CheckId),
        CONSTRAINT CK_RiskCheckLog_Decision CHECK (Decision IN ('APPROVED', 'REJECTED'))
    );
END;
GO
