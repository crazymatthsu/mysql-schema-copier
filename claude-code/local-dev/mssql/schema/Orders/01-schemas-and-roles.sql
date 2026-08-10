/*
    Orders - schemas and database roles.
*/

IF SCHEMA_ID(N'audit') IS NULL
    EXEC (N'CREATE SCHEMA audit AUTHORIZATION dbo;');
GO

IF DATABASE_PRINCIPAL_ID(N'orders_reader') IS NULL
    CREATE ROLE orders_reader;
GO

IF DATABASE_PRINCIPAL_ID(N'orders_writer') IS NULL
    CREATE ROLE orders_writer;
GO

IF DATABASE_PRINCIPAL_ID(N'orders_executor') IS NULL
    CREATE ROLE orders_executor;
GO
