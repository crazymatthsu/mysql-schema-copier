/*
    Instance-level configuration.

    A DACPAC carries database objects, not instance settings. Anything that lives in
    sp_configure has to be reproduced separately, and these particular settings change
    plan shape - which is the whole point of running against a local SQL Server rather
    than a different engine.

    Run as sa against master before any database is created.
*/

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

/* Matches the enterprise instance: parallelism kept deliberately conservative. */
EXEC sp_configure 'max degree of parallelism', 4;
EXEC sp_configure 'cost threshold for parallelism', 50;
EXEC sp_configure 'optimize for ad hoc workloads', 1;
GO

/*
    Cap the engine well below the container memory limit so the host stays responsive.
    The enterprise instance is sized very differently; this is a local-only value.
*/
EXEC sp_configure 'max server memory (MB)', 3072;
GO

RECONFIGURE;
GO

EXEC sp_configure 'show advanced options', 0;
RECONFIGURE;
GO
