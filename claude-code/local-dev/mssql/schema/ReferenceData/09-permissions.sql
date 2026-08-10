/*
    ReferenceData - role permissions.

    Permissions are granted to roles, never to users: role membership is the only
    environment-specific part, and the provisioner applies it from databases.yaml.
    This is the same shape as the enterprise instance, so the application exercises
    the real permission path instead of running as a database owner.
*/

GRANT SELECT ON SCHEMA::dbo TO ref_reader;
GRANT SELECT ON SCHEMA::mkt TO ref_reader;
GO

GRANT INSERT, UPDATE, DELETE ON SCHEMA::dbo TO ref_writer;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::mkt TO ref_writer;
GO

GRANT EXECUTE ON SCHEMA::dbo TO ref_executor;
GRANT EXECUTE ON SCHEMA::mkt TO ref_executor;
GO

/* Sequence objects need explicit UPDATE for NEXT VALUE FOR. */
GRANT UPDATE ON OBJECT::dbo.InstrumentIdSeq TO ref_writer;
GRANT UPDATE ON OBJECT::dbo.InstrumentIdSeq TO ref_executor;
GO
