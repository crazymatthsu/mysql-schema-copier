/*
    Orders - triggers.

    Every status/fill transition is journalled to audit.OrderEvent. The trigger writes
    to a table the application role is denied UPDATE/DELETE on, so the audit trail can
    only ever grow.
*/

CREATE OR ALTER TRIGGER dbo.trg_Order_Audit
    ON dbo.[Order]
    AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT audit.OrderEvent
        (OrderId, EventType, OldStatusCode, NewStatusCode,
         OldLeavesQty, NewLeavesQty, OldCumQty, NewCumQty)
    SELECT
        i.OrderId,
        CASE
            WHEN d.OrderId IS NULL THEN 'CREATED'
            WHEN i.StatusCode <> d.StatusCode THEN 'STATUS_CHANGE'
            WHEN i.CumQty <> d.CumQty THEN 'FILL'
            ELSE 'AMEND'
        END,
        d.StatusCode,
        i.StatusCode,
        d.LeavesQty,
        i.LeavesQty,
        d.CumQty,
        i.CumQty
    FROM inserted AS i
    LEFT JOIN deleted AS d
        ON d.OrderId = i.OrderId;
END;
GO
