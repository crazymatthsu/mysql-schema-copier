/*
    Linked servers.

    The enterprise instance defines linked servers for market data and settlement feeds.
    They are deliberately NOT recreated locally:

      - a local linked server pointing at a corporate host drags production endpoints
        onto developer machines, which is exactly what this local environment avoids;
      - a loopback linked server aliasing the local instance would let four-part names
        resolve, but it also silently changes transaction semantics (any statement
        touching it is promoted to a distributed transaction).

    The supported local approach is to keep application code on three-part names, which
    work because the local databases carry the same names as the enterprise ones. Where
    a four-part name is unavoidable, mock the remote object with a local view or table
    in the owning database rather than adding a linked server here.

    If a team does need one, this is the shape - kept as documentation, not executed:

        EXEC sp_addlinkedserver
            @server     = N'SQL01',
            @srvproduct = N'',
            @provider   = N'MSOLEDBSQL',
            @datasrc    = N'localhost,1433';

        EXEC sp_addlinkedsrvlogin
            @rmtsrvname  = N'SQL01',
            @useself     = N'False',
            @rmtuser     = N'<local login>',
            @rmtpassword = N'<local password>';
*/

PRINT 'Linked servers: none created locally by design (see server/02-linked-servers.sql).';
GO
