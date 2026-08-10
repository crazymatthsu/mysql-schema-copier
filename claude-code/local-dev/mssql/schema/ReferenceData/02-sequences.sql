/*
    ReferenceData - sequences.

    Instrument identifiers come from a sequence rather than IDENTITY so that seed data
    and application inserts can reserve keys before the row exists, which is how the
    upstream trading platform allocates instrument ids.
*/

IF OBJECT_ID(N'dbo.InstrumentIdSeq', N'SO') IS NULL
    CREATE SEQUENCE dbo.InstrumentIdSeq
        AS INT
        START WITH 100000
        INCREMENT BY 1
        MINVALUE 100000
        NO CYCLE
        CACHE 50;
GO
