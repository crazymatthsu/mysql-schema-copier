/*
    Trading - functions.
*/

CREATE OR ALTER FUNCTION dbo.ufn_NetPositionQty
(
    @AccountId    INT,
    @InstrumentId INT
)
RETURNS DECIMAL(19, 4)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Qty DECIMAL(19, 4);

    SELECT @Qty = p.Quantity
    FROM dbo.Position AS p
    WHERE p.AccountId = @AccountId
      AND p.InstrumentId = @InstrumentId;

    RETURN ISNULL(@Qty, 0);
END;
GO
