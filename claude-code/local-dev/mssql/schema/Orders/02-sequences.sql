/*
    Orders - sequences.

    Order and execution ids come from sequences so the gateway can stamp an id onto a
    FIX message before the row is written, and so ids stay unique across partitions.
*/

IF OBJECT_ID(N'dbo.OrderIdSeq', N'SO') IS NULL
    CREATE SEQUENCE dbo.OrderIdSeq
        AS BIGINT
        START WITH 1000000
        INCREMENT BY 1
        MINVALUE 1000000
        NO CYCLE
        CACHE 100;
GO

IF OBJECT_ID(N'dbo.ExecutionIdSeq', N'SO') IS NULL
    CREATE SEQUENCE dbo.ExecutionIdSeq
        AS BIGINT
        START WITH 5000000
        INCREMENT BY 1
        MINVALUE 5000000
        NO CYCLE
        CACHE 100;
GO
