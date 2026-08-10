/*
    Validation - server and database settings.

    Every validation script returns result sets shaped (CheckName, Detail, Passed).
    The runner collects any result set with those columns and ignores the rest, so a
    script is free to EXEC procedures that emit their own output.

    Run against master; all references use three-part names.
*/

SELECT
    CheckName = N'Server edition is Developer',
    Detail    = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(200)),
    Passed    = CASE WHEN CAST(SERVERPROPERTY('Edition') AS NVARCHAR(200)) LIKE N'Developer%' THEN 1 ELSE 0 END;

SELECT
    CheckName = N'Server major version is 16 (SQL Server 2022)',
    Detail    = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(200)),
    Passed    = CASE WHEN CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(200)) LIKE N'16.%' THEN 1 ELSE 0 END;

SELECT
    CheckName = N'Server collation matches enterprise',
    Detail    = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(200)),
    Passed    = CASE WHEN CAST(SERVERPROPERTY('Collation') AS NVARCHAR(200)) = N'SQL_Latin1_General_CP1_CI_AS' THEN 1 ELSE 0 END;

SELECT
    CheckName = N'Database exists: ' + d.name,
    Detail    = CONCAT(N'collation=', d.collation_name,
                       N' compat=', d.compatibility_level,
                       N' rcsi=', d.is_read_committed_snapshot_on,
                       N' state=', d.state_desc),
    Passed    = CASE
        WHEN d.collation_name = N'SQL_Latin1_General_CP1_CI_AS'
         AND d.compatibility_level = 150
         AND d.state_desc = N'ONLINE'
        THEN 1 ELSE 0
    END
FROM sys.databases AS d
WHERE d.name IN (N'ReferenceData', N'Trading', N'Orders', N'Risk');

SELECT
    CheckName = N'All four application databases present',
    Detail    = CAST(COUNT(*) AS NVARCHAR(20)) + N' of 4',
    Passed    = CASE WHEN COUNT(*) = 4 THEN 1 ELSE 0 END
FROM sys.databases AS d
WHERE d.name IN (N'ReferenceData', N'Trading', N'Orders', N'Risk');

SELECT
    CheckName = N'Application logins exist',
    Detail    = CAST(COUNT(*) AS NVARCHAR(20)) + N' of 5',
    Passed    = CASE WHEN COUNT(*) = 5 THEN 1 ELSE 0 END
FROM sys.server_principals AS p
WHERE p.name IN (N'trading_app', N'orders_app', N'risk_app', N'refdata_app', N'report_reader')
  AND p.type = 'S';
