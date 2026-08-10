/*
    Orders - lookup tables.

    These are foreign key targets, so the database is not usable until they are loaded:
    treat them as reference data that ships with the schema, not as test data.
*/

MERGE dbo.OrderSide AS tgt
USING
(
    VALUES
        ('BUY',  N'Buy'),
        ('SELL', N'Sell')
) AS src (SideCode, Description)
    ON tgt.SideCode = src.SideCode
WHEN MATCHED THEN
    UPDATE SET tgt.Description = src.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SideCode, Description) VALUES (src.SideCode, src.Description);
GO

MERGE dbo.OrderType AS tgt
USING
(
    VALUES
        ('MARKET',     N'Market',            0, 0),
        ('LIMIT',      N'Limit',             1, 0),
        ('STOP',       N'Stop',              0, 1),
        ('STOP_LIMIT', N'Stop limit',        1, 1)
) AS src (OrderTypeCode, Description, RequiresLimit, RequiresStop)
    ON tgt.OrderTypeCode = src.OrderTypeCode
WHEN MATCHED THEN
    UPDATE SET
        tgt.Description   = src.Description,
        tgt.RequiresLimit = src.RequiresLimit,
        tgt.RequiresStop  = src.RequiresStop
WHEN NOT MATCHED BY TARGET THEN
    INSERT (OrderTypeCode, Description, RequiresLimit, RequiresStop)
    VALUES (src.OrderTypeCode, src.Description, src.RequiresLimit, src.RequiresStop);
GO

MERGE dbo.TimeInForce AS tgt
USING
(
    VALUES
        ('DAY', N'Good for day'),
        ('GTC', N'Good till cancel'),
        ('IOC', N'Immediate or cancel'),
        ('FOK', N'Fill or kill')
) AS src (TifCode, Description)
    ON tgt.TifCode = src.TifCode
WHEN MATCHED THEN
    UPDATE SET tgt.Description = src.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (TifCode, Description) VALUES (src.TifCode, src.Description);
GO

MERGE dbo.OrderStatus AS tgt
USING
(
    VALUES
        ('PENDING_NEW',      N'Pending new',       0),
        ('NEW',              N'New',               0),
        ('PARTIALLY_FILLED', N'Partially filled',  0),
        ('FILLED',           N'Filled',            1),
        ('PENDING_CANCEL',   N'Pending cancel',    0),
        ('CANCELED',         N'Canceled',          1),
        ('REJECTED',         N'Rejected',          1),
        ('EXPIRED',          N'Expired',           1)
) AS src (StatusCode, Description, IsTerminal)
    ON tgt.StatusCode = src.StatusCode
WHEN MATCHED THEN
    UPDATE SET tgt.Description = src.Description, tgt.IsTerminal = src.IsTerminal
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StatusCode, Description, IsTerminal)
    VALUES (src.StatusCode, src.Description, src.IsTerminal);
GO
