/*
    ReferenceData - schemas and database roles.

    Schemas and roles are database-level objects: an enterprise DACPAC carries them,
    so the local clone must create them too. Only the *membership* of those roles is
    environment-specific, and that is applied by the provisioner from databases.yaml.
*/

IF SCHEMA_ID(N'mkt') IS NULL
    EXEC (N'CREATE SCHEMA mkt AUTHORIZATION dbo;');
GO

IF DATABASE_PRINCIPAL_ID(N'ref_reader') IS NULL
    CREATE ROLE ref_reader;
GO

IF DATABASE_PRINCIPAL_ID(N'ref_writer') IS NULL
    CREATE ROLE ref_writer;
GO

IF DATABASE_PRINCIPAL_ID(N'ref_executor') IS NULL
    CREATE ROLE ref_executor;
GO
