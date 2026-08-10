/*
    Risk - schemas and database roles.
*/

IF DATABASE_PRINCIPAL_ID(N'risk_reader') IS NULL
    CREATE ROLE risk_reader;
GO

IF DATABASE_PRINCIPAL_ID(N'risk_writer') IS NULL
    CREATE ROLE risk_writer;
GO

IF DATABASE_PRINCIPAL_ID(N'risk_executor') IS NULL
    CREATE ROLE risk_executor;
GO
