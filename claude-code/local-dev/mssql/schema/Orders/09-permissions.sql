/*
    Orders - role permissions.
*/

GRANT SELECT ON SCHEMA::dbo TO orders_reader;
GRANT SELECT ON SCHEMA::audit TO orders_reader;
GO

GRANT INSERT, UPDATE ON OBJECT::dbo.[Order] TO orders_writer;
GRANT INSERT ON OBJECT::dbo.Execution TO orders_writer;
GO

GRANT EXECUTE ON SCHEMA::dbo TO orders_executor;
GO

/* NEXT VALUE FOR needs UPDATE on the sequence when the insert is not wrapped in a proc. */
GRANT UPDATE ON OBJECT::dbo.OrderIdSeq TO orders_writer;
GRANT UPDATE ON OBJECT::dbo.ExecutionIdSeq TO orders_writer;
GO

/*
    Orders are never hard-deleted, and the audit journal is append-only.

    The audit DENY covers UPDATE and DELETE only. INSERT is left alone deliberately: the
    rows are written by dbo.trg_Order_Audit, and relying on ownership chaining to step over
    a DENY would be a fragile thing to build the audit trail on. Nothing grants the
    application INSERT on the audit schema either way, so it still cannot write there
    directly.
*/
DENY DELETE ON OBJECT::dbo.[Order] TO orders_writer;
DENY DELETE ON OBJECT::dbo.Execution TO orders_writer;
DENY UPDATE, DELETE ON SCHEMA::audit TO orders_writer;
GO
