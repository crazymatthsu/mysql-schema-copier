/*
    Risk - role permissions.
*/

GRANT SELECT ON SCHEMA::dbo TO risk_reader;
GO

GRANT INSERT, UPDATE, DELETE ON OBJECT::dbo.RiskLimit TO risk_writer;
GRANT INSERT ON OBJECT::dbo.RiskCheckLog TO risk_writer;
GO

GRANT EXECUTE ON SCHEMA::dbo TO risk_executor;
GO

/* The pre-trade audit log is append-only. */
DENY UPDATE, DELETE ON OBJECT::dbo.RiskCheckLog TO risk_writer;
GO
