/*
    Trading - role permissions.

    Writers get INSERT/UPDATE on the mutable tables only. Position and CashBalance are
    deliberately not writable directly: every change goes through usp_ApplyExecution,
    which is what trading_executor is for.
*/

GRANT SELECT ON SCHEMA::dbo TO trading_reader;
GO

GRANT INSERT, UPDATE, DELETE ON OBJECT::dbo.Account TO trading_writer;
GRANT INSERT, UPDATE, DELETE ON OBJECT::dbo.Trader  TO trading_writer;
GRANT INSERT, UPDATE, DELETE ON OBJECT::dbo.Book    TO trading_writer;
GO

GRANT EXECUTE ON SCHEMA::dbo TO trading_executor;
GO

/* The audit table is append-only for everyone except the trigger itself. */
DENY DELETE, UPDATE ON OBJECT::dbo.PositionHistory TO trading_writer;
GO
