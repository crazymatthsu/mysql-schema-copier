/*
    Trading - triggers.

    Position changes are audited by a trigger rather than by application code, so the
    clone has to reproduce it or local writes will silently skip the audit trail.
*/

CREATE OR ALTER TRIGGER dbo.trg_Position_Audit
    ON dbo.Position
    AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT dbo.PositionHistory (AccountId, InstrumentId, ChangeType, Quantity, AvgPrice, RealizedPnL)
    SELECT
        i.AccountId,
        i.InstrumentId,
        CASE WHEN EXISTS (SELECT 1 FROM deleted AS d WHERE d.AccountId = i.AccountId AND d.InstrumentId = i.InstrumentId)
             THEN 'U' ELSE 'I' END,
        i.Quantity,
        i.AvgPrice,
        i.RealizedPnL
    FROM inserted AS i;

    INSERT dbo.PositionHistory (AccountId, InstrumentId, ChangeType, Quantity, AvgPrice, RealizedPnL)
    SELECT
        d.AccountId,
        d.InstrumentId,
        'D',
        d.Quantity,
        d.AvgPrice,
        d.RealizedPnL
    FROM deleted AS d
    WHERE NOT EXISTS (SELECT 1 FROM inserted AS i WHERE i.AccountId = d.AccountId AND i.InstrumentId = d.InstrumentId);
END;
GO
