/*
    Risk - indexes.

    A UNIQUE constraint would allow only one NULL InstrumentId per table, so the
    "one account-wide default per account" rule is expressed as two filtered indexes.
*/

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_RiskLimit_AccountDefault' AND object_id = OBJECT_ID(N'dbo.RiskLimit'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_RiskLimit_AccountDefault
        ON dbo.RiskLimit (AccountId)
        WHERE InstrumentId IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_RiskLimit_AccountInstrument' AND object_id = OBJECT_ID(N'dbo.RiskLimit'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_RiskLimit_AccountInstrument
        ON dbo.RiskLimit (AccountId, InstrumentId)
        WHERE InstrumentId IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_RiskCheckLog_Account_CheckedAt' AND object_id = OBJECT_ID(N'dbo.RiskCheckLog'))
    CREATE NONCLUSTERED INDEX IX_RiskCheckLog_Account_CheckedAt
        ON dbo.RiskCheckLog (AccountId, CheckedAtUtc DESC)
        INCLUDE (InstrumentId, Decision, ReasonCode);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_RiskCheckLog_Rejected' AND object_id = OBJECT_ID(N'dbo.RiskCheckLog'))
    CREATE NONCLUSTERED INDEX IX_RiskCheckLog_Rejected
        ON dbo.RiskCheckLog (CheckedAtUtc DESC)
        INCLUDE (AccountId, InstrumentId, ReasonCode)
        WHERE Decision = 'REJECTED';
GO
