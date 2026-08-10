/*
    Trading - books, traders and accounts.

    Account ids are explicit (not IDENTITY) because the enterprise instance allocates
    them upstream; keeping the same ids locally means test fixtures and saved queries
    move between environments unchanged.
*/

MERGE dbo.Book AS tgt
USING
(
    VALUES
        ('EQ-US',   N'US Cash Equities',     'DESK-AMER', 'USD'),
        ('EQ-EU',   N'European Equities',    'DESK-EMEA', 'GBP'),
        ('EQ-APAC', N'Asia Pacific Equities','DESK-APAC', 'JPY')
) AS src (BookCode, BookName, DeskCode, BaseCurrency)
    ON tgt.BookCode = src.BookCode
WHEN MATCHED THEN
    UPDATE SET tgt.BookName = src.BookName, tgt.DeskCode = src.DeskCode, tgt.BaseCurrency = src.BaseCurrency
WHEN NOT MATCHED BY TARGET THEN
    INSERT (BookCode, BookName, DeskCode, BaseCurrency)
    VALUES (src.BookCode, src.BookName, src.DeskCode, src.BaseCurrency);
GO

MERGE dbo.Trader AS tgt
USING
(
    VALUES
        ('TRD-001', N'Alex Nguyen',    'DESK-AMER'),
        ('TRD-002', N'Priya Raman',    'DESK-AMER'),
        ('TRD-003', N'Sam Okafor',     'DESK-EMEA'),
        ('TRD-004', N'Yuki Tanaka',    'DESK-APAC'),
        ('TRD-005', N'Robin Delacroix','DESK-EMEA')
) AS src (TraderCode, TraderName, DeskCode)
    ON tgt.TraderCode = src.TraderCode
WHEN MATCHED THEN
    UPDATE SET tgt.TraderName = src.TraderName, tgt.DeskCode = src.DeskCode
WHEN NOT MATCHED BY TARGET THEN
    INSERT (TraderCode, TraderName, DeskCode)
    VALUES (src.TraderCode, src.TraderName, src.DeskCode);
GO

MERGE dbo.Account AS tgt
USING
(
    SELECT
        a.AccountId,
        a.AccountCode,
        a.AccountName,
        a.AccountType,
        a.BaseCurrency,
        b.BookId
    FROM
    (
        VALUES
            (1001, 'TEST_ACCOUNT_1', N'Aurora Capital Partners', 'CLIENT', 'USD', 'EQ-US'),
            (1002, 'TEST_ACCOUNT_2', N'Borealis Global Fund',    'CLIENT', 'USD', 'EQ-US'),
            (1003, 'FIRM_PRINCIPAL', N'Firm Principal Desk',     'FIRM',   'USD', 'EQ-US'),
            (1004, 'TEST_ACCOUNT_3', N'Cyan Asset Management',   'CLIENT', 'GBP', 'EQ-EU'),
            (1005, 'HEDGE_BOOK_1',   N'Delta Hedge Book',        'HEDGE',  'USD', 'EQ-EU'),
            (1006, 'TEST_ACCOUNT_4', N'Eastwind Partners KK',    'CLIENT', 'JPY', 'EQ-APAC')
    ) AS a (AccountId, AccountCode, AccountName, AccountType, BaseCurrency, BookCode)
    INNER JOIN dbo.Book AS b
        ON b.BookCode = a.BookCode
) AS src
    ON tgt.AccountId = src.AccountId
WHEN MATCHED THEN
    UPDATE SET
        tgt.AccountCode  = src.AccountCode,
        tgt.AccountName  = src.AccountName,
        tgt.AccountType  = src.AccountType,
        tgt.BaseCurrency = src.BaseCurrency,
        tgt.BookId       = src.BookId,
        tgt.IsActive     = 1
WHEN NOT MATCHED BY TARGET THEN
    INSERT (AccountId, AccountCode, AccountName, AccountType, BaseCurrency, BookId)
    VALUES (src.AccountId, src.AccountCode, src.AccountName, src.AccountType, src.BaseCurrency, src.BookId);
GO
