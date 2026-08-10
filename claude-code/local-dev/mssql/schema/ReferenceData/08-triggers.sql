/*
    ReferenceData - triggers.
*/

CREATE OR ALTER TRIGGER dbo.trg_Instrument_SetUpdatedAt
    ON dbo.Instrument
    AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;

    UPDATE i
    SET i.UpdatedAtUtc = SYSUTCDATETIME()
    FROM dbo.Instrument AS i
    INNER JOIN inserted AS ins
        ON ins.InstrumentId = i.InstrumentId;
END;
GO
