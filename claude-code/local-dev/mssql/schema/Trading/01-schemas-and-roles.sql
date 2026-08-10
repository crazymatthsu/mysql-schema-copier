/*
    Trading - schemas and database roles.

    The role names mirror the enterprise instance so the application exercises the same
    login -> user -> role -> object permission chain locally.
*/

IF DATABASE_PRINCIPAL_ID(N'trading_reader') IS NULL
    CREATE ROLE trading_reader;
GO

IF DATABASE_PRINCIPAL_ID(N'trading_writer') IS NULL
    CREATE ROLE trading_writer;
GO

IF DATABASE_PRINCIPAL_ID(N'trading_executor') IS NULL
    CREATE ROLE trading_executor;
GO
