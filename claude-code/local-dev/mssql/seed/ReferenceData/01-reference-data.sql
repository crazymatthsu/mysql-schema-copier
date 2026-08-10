/*
    ReferenceData - static reference data.

    Synthetic, not production-derived. Every statement is a MERGE so the file can be
    replayed against an existing database without duplicating rows, which is what makes
    `local-env seed` safe to run repeatedly.
*/

MERGE dbo.Currency AS tgt
USING
(
    VALUES
        ('USD', N'US Dollar',        2),
        ('EUR', N'Euro',             2),
        ('GBP', N'British Pound',    2),
        ('JPY', N'Japanese Yen',     0),
        ('HKD', N'Hong Kong Dollar', 2),
        ('CAD', N'Canadian Dollar',  2),
        ('CHF', N'Swiss Franc',      2),
        ('AUD', N'Australian Dollar', 2)
) AS src (CurrencyCode, CurrencyName, MinorUnits)
    ON tgt.CurrencyCode = src.CurrencyCode
WHEN MATCHED THEN
    UPDATE SET tgt.CurrencyName = src.CurrencyName, tgt.MinorUnits = src.MinorUnits
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CurrencyCode, CurrencyName, MinorUnits) VALUES (src.CurrencyCode, src.CurrencyName, src.MinorUnits);
GO

MERGE dbo.Country AS tgt
USING
(
    VALUES
        ('US', N'United States'),
        ('GB', N'United Kingdom'),
        ('JP', N'Japan'),
        ('HK', N'Hong Kong'),
        ('CA', N'Canada'),
        ('DE', N'Germany')
) AS src (CountryCode, CountryName)
    ON tgt.CountryCode = src.CountryCode
WHEN MATCHED THEN
    UPDATE SET tgt.CountryName = src.CountryName
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CountryCode, CountryName) VALUES (src.CountryCode, src.CountryName);
GO

MERGE dbo.Exchange AS tgt
USING
(
    VALUES
        ('XNYS', N'New York Stock Exchange', 'US', 'USD', 'America/New_York', '14:30', '21:00'),
        ('XNAS', N'Nasdaq Stock Market',     'US', 'USD', 'America/New_York', '14:30', '21:00'),
        ('XLON', N'London Stock Exchange',   'GB', 'GBP', 'Europe/London',    '08:00', '16:30'),
        ('XTKS', N'Tokyo Stock Exchange',    'JP', 'JPY', 'Asia/Tokyo',       '00:00', '06:00'),
        ('XHKG', N'Hong Kong Exchange',      'HK', 'HKD', 'Asia/Hong_Kong',   '01:30', '08:00'),
        ('XTSE', N'Toronto Stock Exchange',  'CA', 'CAD', 'America/Toronto',  '14:30', '21:00')
) AS src (Mic, ExchangeName, CountryCode, CurrencyCode, TimeZoneName, OpenTimeUtc, CloseTimeUtc)
    ON tgt.Mic = src.Mic
WHEN MATCHED THEN
    UPDATE SET
        tgt.ExchangeName = src.ExchangeName,
        tgt.CountryCode  = src.CountryCode,
        tgt.CurrencyCode = src.CurrencyCode,
        tgt.TimeZoneName = src.TimeZoneName,
        tgt.OpenTimeUtc  = src.OpenTimeUtc,
        tgt.CloseTimeUtc = src.CloseTimeUtc
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Mic, ExchangeName, CountryCode, CurrencyCode, TimeZoneName, OpenTimeUtc, CloseTimeUtc)
    VALUES (src.Mic, src.ExchangeName, src.CountryCode, src.CurrencyCode, src.TimeZoneName, src.OpenTimeUtc, src.CloseTimeUtc);
GO

/*
    Instrument universe. Lot sizes follow venue convention (1 in North America and
    London, 100 in Tokyo and Hong Kong) so that the odd-lot rejection path in
    Orders.dbo.usp_PlaceOrder is reachable with realistic data.
*/
WITH src AS
(
    SELECT *
    FROM
    (
        VALUES
            ('AAPL',  'XNAS', N'Apple Inc.',                  'EQUITY', 'TECH',      'US0378331005', 1,   0.01),
            ('MSFT',  'XNAS', N'Microsoft Corporation',       'EQUITY', 'TECH',      'US5949181045', 1,   0.01),
            ('AMZN',  'XNAS', N'Amazon.com Inc.',             'EQUITY', 'RETAIL',    'US0231351067', 1,   0.01),
            ('GOOGL', 'XNAS', N'Alphabet Inc. Class A',       'EQUITY', 'TECH',      'US02079K3059', 1,   0.01),
            ('NVDA',  'XNAS', N'NVIDIA Corporation',          'EQUITY', 'SEMI',      'US67066G1040', 1,   0.01),
            ('META',  'XNAS', N'Meta Platforms Inc.',         'EQUITY', 'TECH',      'US30303M1027', 1,   0.01),
            ('TSLA',  'XNAS', N'Tesla Inc.',                  'EQUITY', 'AUTO',      'US88160R1014', 1,   0.01),
            ('INTC',  'XNAS', N'Intel Corporation',           'EQUITY', 'SEMI',      'US4581401001', 1,   0.01),
            ('CSCO',  'XNAS', N'Cisco Systems Inc.',          'EQUITY', 'TECH',      'US17275R1023', 1,   0.01),
            ('QQQ',   'XNAS', N'Invesco QQQ Trust',           'ETF',    'INDEX',     'US46090E1038', 1,   0.01),
            ('IBM',   'XNYS', N'International Business Mach', 'EQUITY', 'TECH',      'US4592001014', 1,   0.01),
            ('JPM',   'XNYS', N'JPMorgan Chase & Co.',        'EQUITY', 'FINANCIAL', 'US46625H1005', 1,   0.01),
            ('XOM',   'XNYS', N'Exxon Mobil Corporation',     'EQUITY', 'ENERGY',    'US30231G1022', 1,   0.01),
            ('KO',    'XNYS', N'Coca-Cola Company',           'EQUITY', 'CONSUMER',  'US1912161007', 1,   0.01),
            ('PFE',   'XNYS', N'Pfizer Inc.',                 'EQUITY', 'HEALTH',    'US7170811035', 1,   0.01),
            ('WMT',   'XNYS', N'Walmart Inc.',                'EQUITY', 'RETAIL',    'US9311421039', 1,   0.01),
            ('DIS',   'XNYS', N'Walt Disney Company',         'EQUITY', 'MEDIA',     'US2546871060', 1,   0.01),
            ('BA',    'XNYS', N'Boeing Company',              'EQUITY', 'INDUSTRIAL','US0970231058', 1,   0.01),
            ('CVX',   'XNYS', N'Chevron Corporation',         'EQUITY', 'ENERGY',    'US1667641005', 1,   0.01),
            ('SPY',   'XNYS', N'SPDR S&P 500 ETF Trust',      'ETF',    'INDEX',     'US78462F1030', 1,   0.01),
            ('VOD',   'XLON', N'Vodafone Group plc',          'EQUITY', 'TELECOM',   'GB00BH4HKS39', 1,   0.01),
            ('HSBA',  'XLON', N'HSBC Holdings plc',           'EQUITY', 'FINANCIAL', 'GB0005405286', 1,   0.01),
            ('BP',    'XLON', N'BP plc',                      'EQUITY', 'ENERGY',    'GB0007980591', 1,   0.01),
            ('RIO',   'XLON', N'Rio Tinto plc',               'EQUITY', 'MINING',    'GB0007188757', 1,   0.01),
            ('AZN',   'XLON', N'AstraZeneca plc',             'EQUITY', 'HEALTH',    'GB0009895292', 1,   0.01),
            ('7203',  'XTKS', N'Toyota Motor Corporation',    'EQUITY', 'AUTO',      'JP3633400001', 100, 0.50),
            ('6758',  'XTKS', N'Sony Group Corporation',      'EQUITY', 'TECH',      'JP3435000009', 100, 0.50),
            ('9984',  'XTKS', N'SoftBank Group Corp.',        'EQUITY', 'TELECOM',   'JP3436100006', 100, 0.50),
            ('0700',  'XHKG', N'Tencent Holdings Ltd.',       'EQUITY', 'TECH',      'KYG875721634', 100, 0.20),
            ('0005',  'XHKG', N'HSBC Holdings plc (HK)',      'EQUITY', 'FINANCIAL', 'GB0005405286', 100, 0.20),
            ('RY',    'XTSE', N'Royal Bank of Canada',        'EQUITY', 'FINANCIAL', 'CA7800871021', 1,   0.01),
            ('TD',    'XTSE', N'Toronto-Dominion Bank',       'EQUITY', 'FINANCIAL', 'CA8911605092', 1,   0.01)
    ) AS v (Symbol, Mic, InstrumentName, InstrumentType, SectorCode, Isin, LotSize, TickSize)
)
MERGE dbo.Instrument AS tgt
USING
(
    SELECT
        s.Symbol,
        e.ExchangeId,
        s.InstrumentName,
        s.InstrumentType,
        s.SectorCode,
        /* The HK line of HSBC shares an ISIN with the London line; the unique index is
           filtered on NOT NULL, so only one of the two may carry it. */
        Isin = CASE WHEN s.Mic = 'XHKG' AND s.Symbol = '0005' THEN NULL ELSE s.Isin END,
        s.LotSize,
        s.TickSize,
        e.CurrencyCode
    FROM src AS s
    INNER JOIN dbo.Exchange AS e
        ON e.Mic = s.Mic
) AS src2
    ON tgt.ExchangeId = src2.ExchangeId
   AND tgt.Symbol = src2.Symbol
WHEN MATCHED THEN
    UPDATE SET
        tgt.InstrumentName = src2.InstrumentName,
        tgt.InstrumentType = src2.InstrumentType,
        tgt.SectorCode     = src2.SectorCode,
        tgt.Isin           = src2.Isin,
        tgt.LotSize        = src2.LotSize,
        tgt.TickSize       = src2.TickSize,
        tgt.CurrencyCode   = src2.CurrencyCode,
        tgt.IsActive       = 1
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Symbol, ExchangeId, InstrumentName, InstrumentType, SectorCode, Isin, LotSize, TickSize, CurrencyCode)
    VALUES (src2.Symbol, src2.ExchangeId, src2.InstrumentName, src2.InstrumentType, src2.SectorCode,
            src2.Isin, src2.LotSize, src2.TickSize, src2.CurrencyCode);
GO
