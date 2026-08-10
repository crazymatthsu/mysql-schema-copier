USE ReferenceData;
GO

DROP VIEW IF EXISTS dbo.vActiveInstrument;
DROP TABLE IF EXISTS dbo.Instrument;
DROP TABLE IF EXISTS dbo.Exchange;
DROP TABLE IF EXISTS dbo.InstrumentType;
DROP TABLE IF EXISTS dbo.Currency;
GO

CREATE TABLE dbo.Currency (
    CurrencyCode char(3) NOT NULL CONSTRAINT PK_Currency PRIMARY KEY,
    CurrencyName nvarchar(64) NOT NULL,
    MinorUnit tinyint NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Currency_IsActive DEFAULT 1
);
GO

CREATE TABLE dbo.Exchange (
    ExchangeCode varchar(12) NOT NULL CONSTRAINT PK_Exchange PRIMARY KEY,
    ExchangeName nvarchar(128) NOT NULL,
    MicCode varchar(8) NOT NULL,
    TimeZoneName varchar(64) NOT NULL,
    CurrencyCode char(3) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Exchange_IsActive DEFAULT 1,
    CONSTRAINT FK_Exchange_Currency FOREIGN KEY (CurrencyCode) REFERENCES dbo.Currency(CurrencyCode)
);
GO

CREATE TABLE dbo.InstrumentType (
    InstrumentTypeCode varchar(16) NOT NULL CONSTRAINT PK_InstrumentType PRIMARY KEY,
    InstrumentTypeName nvarchar(64) NOT NULL
);
GO

CREATE TABLE dbo.Instrument (
    InstrumentId int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Instrument PRIMARY KEY,
    Symbol varchar(32) NOT NULL,
    InstrumentName nvarchar(160) NOT NULL,
    InstrumentTypeCode varchar(16) NOT NULL,
    ExchangeCode varchar(12) NOT NULL,
    CurrencyCode char(3) NOT NULL,
    Cusip varchar(16) NULL,
    Isin varchar(16) NULL,
    TickSize decimal(18, 8) NOT NULL,
    LotSize int NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Instrument_IsActive DEFAULT 1,
    CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_Instrument_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Instrument_Symbol_Exchange UNIQUE (Symbol, ExchangeCode),
    CONSTRAINT FK_Instrument_Type FOREIGN KEY (InstrumentTypeCode) REFERENCES dbo.InstrumentType(InstrumentTypeCode),
    CONSTRAINT FK_Instrument_Exchange FOREIGN KEY (ExchangeCode) REFERENCES dbo.Exchange(ExchangeCode),
    CONSTRAINT FK_Instrument_Currency FOREIGN KEY (CurrencyCode) REFERENCES dbo.Currency(CurrencyCode)
);
GO

CREATE INDEX IX_Instrument_Type ON dbo.Instrument(InstrumentTypeCode, IsActive);
GO

CREATE OR ALTER VIEW dbo.vActiveInstrument
AS
SELECT
    i.InstrumentId,
    i.Symbol,
    i.InstrumentName,
    i.InstrumentTypeCode,
    it.InstrumentTypeName,
    i.ExchangeCode,
    e.ExchangeName,
    i.CurrencyCode,
    i.TickSize,
    i.LotSize
FROM dbo.Instrument AS i
JOIN dbo.InstrumentType AS it ON it.InstrumentTypeCode = i.InstrumentTypeCode
JOIN dbo.Exchange AS e ON e.ExchangeCode = i.ExchangeCode
WHERE i.IsActive = 1
  AND e.IsActive = 1;
GO
