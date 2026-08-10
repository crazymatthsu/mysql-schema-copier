/*
    ReferenceData - tables.

    Static reference data shared by every trading application: currencies, countries,
    exchanges, instruments, and the market-data snapshots used for valuation.
*/

IF OBJECT_ID(N'dbo.Currency', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Currency
    (
        CurrencyCode  CHAR(3)        NOT NULL,
        CurrencyName  NVARCHAR(60)   NOT NULL,
        MinorUnits    TINYINT        NOT NULL CONSTRAINT DF_Currency_MinorUnits DEFAULT (2),
        IsActive      BIT            NOT NULL CONSTRAINT DF_Currency_IsActive DEFAULT (1),
        CONSTRAINT PK_Currency PRIMARY KEY CLUSTERED (CurrencyCode),
        CONSTRAINT CK_Currency_MinorUnits CHECK (MinorUnits BETWEEN 0 AND 4)
    );
END;
GO

IF OBJECT_ID(N'dbo.Country', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Country
    (
        CountryCode  CHAR(2)       NOT NULL,
        CountryName  NVARCHAR(60)  NOT NULL,
        CONSTRAINT PK_Country PRIMARY KEY CLUSTERED (CountryCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.Exchange', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Exchange
    (
        ExchangeId    INT           NOT NULL IDENTITY(1, 1),
        Mic           CHAR(4)       NOT NULL,
        ExchangeName  NVARCHAR(80)  NOT NULL,
        CountryCode   CHAR(2)       NOT NULL,
        CurrencyCode  CHAR(3)       NOT NULL,
        TimeZoneName  VARCHAR(40)   NOT NULL,
        OpenTimeUtc   TIME(0)       NOT NULL,
        CloseTimeUtc  TIME(0)       NOT NULL,
        IsActive      BIT           NOT NULL CONSTRAINT DF_Exchange_IsActive DEFAULT (1),
        CONSTRAINT PK_Exchange PRIMARY KEY CLUSTERED (ExchangeId),
        CONSTRAINT UQ_Exchange_Mic UNIQUE (Mic),
        CONSTRAINT FK_Exchange_Country FOREIGN KEY (CountryCode)
            REFERENCES dbo.Country (CountryCode),
        CONSTRAINT FK_Exchange_Currency FOREIGN KEY (CurrencyCode)
            REFERENCES dbo.Currency (CurrencyCode)
    );
END;
GO

IF OBJECT_ID(N'dbo.Instrument', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Instrument
    (
        InstrumentId    INT            NOT NULL
            CONSTRAINT DF_Instrument_InstrumentId DEFAULT (NEXT VALUE FOR dbo.InstrumentIdSeq),
        Symbol          VARCHAR(20)    NOT NULL,
        Isin            CHAR(12)       NULL,
        Cusip           CHAR(9)        NULL,
        InstrumentName  NVARCHAR(120)  NOT NULL,
        InstrumentType  VARCHAR(10)    NOT NULL,
        ExchangeId      INT            NOT NULL,
        CurrencyCode    CHAR(3)        NOT NULL,
        SectorCode      VARCHAR(20)    NULL,
        LotSize         INT            NOT NULL CONSTRAINT DF_Instrument_LotSize DEFAULT (1),
        TickSize        DECIMAL(19, 6) NOT NULL CONSTRAINT DF_Instrument_TickSize DEFAULT (0.01),
        IsActive        BIT            NOT NULL CONSTRAINT DF_Instrument_IsActive DEFAULT (1),
        CreatedAtUtc    DATETIME2(3)   NOT NULL CONSTRAINT DF_Instrument_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc    DATETIME2(3)   NOT NULL CONSTRAINT DF_Instrument_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        RowVersion      ROWVERSION     NOT NULL,
        CONSTRAINT PK_Instrument PRIMARY KEY CLUSTERED (InstrumentId),
        CONSTRAINT UQ_Instrument_Exchange_Symbol UNIQUE (ExchangeId, Symbol),
        CONSTRAINT FK_Instrument_Exchange FOREIGN KEY (ExchangeId)
            REFERENCES dbo.Exchange (ExchangeId),
        CONSTRAINT FK_Instrument_Currency FOREIGN KEY (CurrencyCode)
            REFERENCES dbo.Currency (CurrencyCode),
        CONSTRAINT CK_Instrument_Type CHECK (InstrumentType IN ('EQUITY', 'ETF', 'ADR', 'PREF')),
        CONSTRAINT CK_Instrument_LotSize CHECK (LotSize > 0),
        CONSTRAINT CK_Instrument_TickSize CHECK (TickSize > 0)
    );
END;
GO

IF OBJECT_ID(N'mkt.PriceSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE mkt.PriceSnapshot
    (
        InstrumentId  INT             NOT NULL,
        AsOfUtc       DATETIME2(3)    NOT NULL,
        BidPx         DECIMAL(19, 6)  NULL,
        AskPx         DECIMAL(19, 6)  NULL,
        LastPx        DECIMAL(19, 6)  NOT NULL,
        VolumeTraded  BIGINT          NOT NULL CONSTRAINT DF_PriceSnapshot_Volume DEFAULT (0),
        Source        VARCHAR(20)     NOT NULL CONSTRAINT DF_PriceSnapshot_Source DEFAULT ('SYNTHETIC'),
        CONSTRAINT PK_PriceSnapshot PRIMARY KEY CLUSTERED (InstrumentId, AsOfUtc),
        CONSTRAINT FK_PriceSnapshot_Instrument FOREIGN KEY (InstrumentId)
            REFERENCES dbo.Instrument (InstrumentId),
        CONSTRAINT CK_PriceSnapshot_LastPx CHECK (LastPx > 0),
        CONSTRAINT CK_PriceSnapshot_Spread CHECK (BidPx IS NULL OR AskPx IS NULL OR BidPx <= AskPx)
    );
END;
GO

IF OBJECT_ID(N'mkt.TradingCalendar', N'U') IS NULL
BEGIN
    CREATE TABLE mkt.TradingCalendar
    (
        ExchangeId    INT           NOT NULL,
        CalendarDate  DATE          NOT NULL,
        IsTradingDay  BIT           NOT NULL,
        HolidayName   NVARCHAR(60)  NULL,
        CONSTRAINT PK_TradingCalendar PRIMARY KEY CLUSTERED (ExchangeId, CalendarDate),
        CONSTRAINT FK_TradingCalendar_Exchange FOREIGN KEY (ExchangeId)
            REFERENCES dbo.Exchange (ExchangeId)
    );
END;
GO
