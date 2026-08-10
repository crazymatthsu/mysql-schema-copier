DECLARE @sql nvarchar(max) = N'';

SELECT @sql = @sql + N'
USE ' + QUOTENAME(name) + N';
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''${APP_LOGIN}'')
    CREATE USER [${APP_LOGIN}] FOR LOGIN [${APP_LOGIN}];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''trading_reader'')
    CREATE ROLE trading_reader;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''trading_writer'')
    CREATE ROLE trading_writer;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''trading_executor'')
    CREATE ROLE trading_executor;
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members AS rm
    JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
    WHERE r.name = N''trading_reader'' AND m.name = N''${APP_LOGIN}''
)
    ALTER ROLE trading_reader ADD MEMBER [${APP_LOGIN}];
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members AS rm
    JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
    WHERE r.name = N''trading_writer'' AND m.name = N''${APP_LOGIN}''
)
    ALTER ROLE trading_writer ADD MEMBER [${APP_LOGIN}];
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members AS rm
    JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
    WHERE r.name = N''trading_executor'' AND m.name = N''${APP_LOGIN}''
)
    ALTER ROLE trading_executor ADD MEMBER [${APP_LOGIN}];
GRANT SELECT TO trading_reader;
GRANT INSERT, UPDATE, DELETE TO trading_writer;
GRANT EXECUTE TO trading_executor;
'
FROM sys.databases
WHERE name IN (N'ReferenceData', N'Trading', N'Orders', N'Risk');

EXEC sys.sp_executesql @sql;
GO
