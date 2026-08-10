/*
    Trading - non-clustered indexes.
*/

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Position_Instrument' AND object_id = OBJECT_ID(N'dbo.Position'))
    CREATE NONCLUSTERED INDEX IX_Position_Instrument
        ON dbo.Position (InstrumentId)
        INCLUDE (Quantity, AvgPrice);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Position_OpenOnly' AND object_id = OBJECT_ID(N'dbo.Position'))
    CREATE NONCLUSTERED INDEX IX_Position_OpenOnly
        ON dbo.Position (AccountId, InstrumentId)
        INCLUDE (Quantity, AvgPrice, RealizedPnL)
        WHERE Quantity <> 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PositionHistory_Account_ChangedAt' AND object_id = OBJECT_ID(N'dbo.PositionHistory'))
    CREATE NONCLUSTERED INDEX IX_PositionHistory_Account_ChangedAt
        ON dbo.PositionHistory (AccountId, ChangedAtUtc DESC)
        INCLUDE (InstrumentId, Quantity, AvgPrice);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Account_Book' AND object_id = OBJECT_ID(N'dbo.Account'))
    CREATE NONCLUSTERED INDEX IX_Account_Book
        ON dbo.Account (BookId)
        INCLUDE (AccountCode, BaseCurrency);
GO
