# Cloning an Enterprise SQL Server Schema into a Local Podman SQL Server

## Goal

Reproduce selected enterprise-hosted Microsoft SQL Server databases inside a local SQL Server container running under Podman so local test applications can read and write against SQL Server in substantially the same way they do against the enterprise instance.

The recommended default approach is:

> **Enterprise SQL Server → schema-only DACPAC → Podman SQL Server Developer → local seed data → local application**

This is generally preferable to copying an entire production database because it is repeatable, safer for developer machines, easier to automate, and does not require production data to be distributed locally.

---

## Recommended Architecture

```text
                 ENTERPRISE / CORPORATE
┌──────────────────────────────────────────────────────┐
│            Enterprise SQL Server                    │
│                                                      │
│   DB_A                DB_B                DB_C        │
│   ├ tables            ├ tables            ...        │
│   ├ views             ├ views                        │
│   ├ procedures        ├ procedures                   │
│   ├ functions         ├ functions                    │
│   ├ sequences         ├ sequences                    │
│   └ permissions       └ permissions                  │
└─────────────┬────────────────────────────────────────┘
              │
              │ SqlPackage Extract
              │ schema only
              ▼
┌──────────────────────────────────────────┐
│         Local provisioning assets       │
│                                          │
│ dacpac/                                  │
│   DB_A.dacpac                            │
│   DB_B.dacpac                            │
│   DB_C.dacpac                            │
│                                          │
│ setup/                                   │
│   01-server-config.sql                   │
│   02-logins.sql                          │
│   03-seed-reference-data.sql             │
│   04-test-data.sql                       │
│                                          │
│ scripts/                                 │
│   refresh-db.sh                          │
└──────────────────┬───────────────────────┘
                   │
                   │ SqlPackage Publish
                   ▼
┌──────────────────────────────────────────────────────┐
│                PODMAN NETWORK                        │
│                                                      │
│ ┌──────────────────────────────┐                     │
│ │ SQL Server Developer        │                     │
│ │                              │                     │
│ │ DB_A                         │                     │
│ │ DB_B                         │                     │
│ │ DB_C                         │                     │
│ │                              │                     │
│ │ local_app_login              │                     │
│ └──────────────┬───────────────┘                     │
│                │                                     │
│                │ jdbc:sqlserver://mssql:1433         │
│                │                                     │
│ ┌──────────────▼───────────────┐                     │
│ │ Your Java test application  │                     │
│ │                              │                     │
│ │ SELECT / INSERT / UPDATE    │                     │
│ │ DELETE / Stored Procedures │                     │
│ └──────────────────────────────┘                     │
└──────────────────────────────────────────────────────┘
```

---

## 1. Match the SQL Server Major Version

If the enterprise environment runs SQL Server 2022, use a SQL Server 2022 container rather than automatically adopting a newer version.

Example:

```bash
podman pull mcr.microsoft.com/mssql/server:2022-latest

podman volume create mssql-data

podman run -d \
  --name mssql \
  --hostname mssql \
  -p 1433:1433 \
  -e ACCEPT_EULA=Y \
  -e MSSQL_PID=Developer \
  -e MSSQL_SA_PASSWORD='YourStrongLocalPassword!' \
  -v mssql-data:/var/opt/mssql \
  mcr.microsoft.com/mssql/server:2022-latest
```

Use **Developer Edition** for a development/test environment. Developer Edition includes Enterprise functionality but is licensed for development and testing rather than production use.

Persist `/var/opt/mssql` using a Podman volume so deleting or recreating the container does not unintentionally destroy the local databases.

### Windows vs. Linux SQL Server

An enterprise SQL Server may run on Windows while the Microsoft SQL Server container runs Linux. Most Database Engine functionality is portable, but verify compatibility if the application depends on features with Linux-specific limitations, such as specialized CLR scenarios, FILESTREAM/FileTable, or certain operational tooling.

---

## 2. Extract Each Enterprise Database into a DACPAC

Suppose the application depends on these databases:

```text
ReferenceData
Trading
Orders
Risk
```

Use `SqlPackage` to extract database definitions from each selected enterprise database.

Example:

```bash
sqlpackage \
  /Action:Extract \
  /SourceConnectionString:"Server=enterprise-sql.mycorp.com;Database=Trading;Integrated Security=true;Encrypt=true;TrustServerCertificate=false" \
  /TargetFile:"./dacpac/Trading.dacpac"
```

Then repeat for the remaining databases:

```bash
sqlpackage \
  /Action:Extract \
  /SourceConnectionString:"Server=enterprise-sql.mycorp.com;Database=Orders;Integrated Security=true;Encrypt=true;TrustServerCertificate=false" \
  /TargetFile:"./dacpac/Orders.dacpac"
```

A DACPAC represents database schema/model definitions rather than being a full production-data backup. It is well suited to reproducibly recreating tables, views, stored procedures, functions, indexes, constraints, and other database objects.

---

## 3. Publish the DACPAC into Podman SQL Server

Publish each DACPAC against the local SQL Server instance.

Example:

```bash
sqlpackage \
  /Action:Publish \
  /SourceFile:"./dacpac/Trading.dacpac" \
  /TargetConnectionString:"Server=localhost,1433;Database=Trading;User ID=sa;Password=YourStrongLocalPassword!;Encrypt=true;TrustServerCertificate=true"
```

For another database:

```bash
sqlpackage \
  /Action:Publish \
  /SourceFile:"./dacpac/Orders.dacpac" \
  /TargetConnectionString:"Server=localhost,1433;Database=Orders;User ID=sa;Password=YourStrongLocalPassword!;Encrypt=true;TrustServerCertificate=true"
```

If the target database does not exist, the publish operation can create it. If it already exists, SqlPackage compares the target against the DACPAC model and applies the required schema changes.

This gives a useful repeatable cycle:

```text
Enterprise schema changes
       ↓
re-extract DACPAC
       ↓
refresh local DB
       ↓
run Java integration tests
```

---

## 4. Reproduce Server-Level Configuration Separately

A database schema clone alone does not always reproduce application behavior.

DACPAC is strong for database-level objects, but instance/server configuration should be handled separately.

Suggested structure:

```text
mssql-local/
│
├── compose.yaml
│
├── dacpac/
│   ├── Trading.dacpac
│   ├── Orders.dacpac
│   └── ReferenceData.dacpac
│
├── server/
│   ├── 01-create-logins.sql
│   ├── 02-server-settings.sql
│   └── 03-linked-servers.sql
│
├── data/
│   ├── Trading-seed.sql
│   ├── Orders-seed.sql
│   └── ReferenceData-seed.sql
│
└── scripts/
    ├── start.sh
    ├── refresh-schema.sh
    ├── seed-data.sh
    └── reset.sh
```

### Items to Check

| Setting / Object | Recommendation |
|---|---|
| Tables | Clone |
| Views | Clone |
| Stored procedures | Clone |
| Functions | Clone |
| Triggers | Clone |
| Sequences | Clone |
| PK/FK/indexes | Clone |
| Schemas | Clone |
| Database roles | Clone/validate |
| Database permissions | Clone/validate |
| SQL Server logins | Re-create locally |
| Server roles | Re-create only as needed |
| Linked servers | Mock or selectively recreate |
| SQL Agent jobs | Usually omit for local development |
| Credentials/secrets | Never copy production secrets |
| Database compatibility level | Match |
| Database collation | Match |
| Server collation | Match where practical |
| Cross-database dependencies | Explicitly verify |

---

## 5. Match Database Compatibility Level

Check the enterprise values:

```sql
SELECT
    name,
    compatibility_level
FROM sys.databases
WHERE name IN (
    'Trading',
    'Orders',
    'ReferenceData'
);
```

Example output:

```text
Trading         150
Orders          150
ReferenceData   150
```

Make the local databases match where appropriate:

```sql
ALTER DATABASE Trading
SET COMPATIBILITY_LEVEL = 150;

ALTER DATABASE Orders
SET COMPATIBILITY_LEVEL = 150;

ALTER DATABASE ReferenceData
SET COMPATIBILITY_LEVEL = 150;
```

Compatibility level can affect T-SQL semantics and query optimizer behavior, so it should be treated as part of environment fidelity.

---

## 6. Match Collation

Check the enterprise SQL Server instance:

```sql
SELECT
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('Collation') AS ServerCollation;
```

Check selected databases:

```sql
SELECT
    name,
    collation_name,
    compatibility_level
FROM sys.databases
WHERE name IN (
    'Trading',
    'Orders',
    'ReferenceData'
);
```

For example:

```text
Enterprise:

Server version      16.x
Server collation    SQL_Latin1_General_CP1_CI_AS

Trading:
collation            SQL_Latin1_General_CP1_CI_AS
compatibility        150
```

Collation affects case sensitivity, accent sensitivity, sorting, comparisons, joins, and potentially temp-table behavior. Matching it can prevent subtle local-vs-enterprise discrepancies.

---

## 7. Re-create Application Logins Locally

Do not make the application use `sa` simply because it is a local environment.

If production uses an application login such as:

```text
trading_app
```

create a local equivalent with a local-only password:

```sql
USE master;
GO

CREATE LOGIN trading_app
WITH PASSWORD = 'LocalTestPassword123!';
GO
```

Then map the login into the application database:

```sql
USE Trading;
GO

CREATE USER trading_app FOR LOGIN trading_app;
GO

ALTER ROLE db_datareader ADD MEMBER trading_app;
ALTER ROLE db_datawriter ADD MEMBER trading_app;
GO
```

A better enterprise-style configuration is to reproduce application-specific roles, for example:

```text
trading_reader
trading_writer
trading_executor
```

rather than giving the application `db_owner`.

A local JDBC configuration might then be:

```properties
jdbc:sqlserver://mssql:1433;
databaseName=Trading;
user=trading_app;
password=LocalTestPassword123!;
```

The application therefore exercises the same logical security flow:

```text
Application
      ↓
SQL authentication
      ↓
database user
      ↓
role
      ↓
table/procedure permissions
```

SQL Server logins are server-level principals, so simply moving a database between instances may leave database users without corresponding server logins. Re-create local logins intentionally.

---

## 8. Preserve Database Names for Cross-Database Queries

Enterprise applications commonly use three-part names or stored procedures that call another database.

Example:

```sql
SELECT *
FROM ReferenceData.dbo.Security s
JOIN Trading.dbo.Position p
  ON s.SecurityId = p.SecurityId;
```

Or:

```sql
EXEC Risk.dbo.CalculateRisk @accountId;
```

If these dependencies exist, recreate all required databases under the same names:

```text
enterprise                 local

SQL01                      mssql:1433
│                          │
├── Trading        →       ├── Trading
├── Orders         →       ├── Orders
├── ReferenceData  →       ├── ReferenceData
└── Risk           →       └── Risk
```

Avoid unnecessary renaming such as:

```text
Trading → LocalTrading     ❌
```

unless the application is guaranteed not to use three-part database names.

Keeping database names identical removes an entire class of local-environment differences.

---

## 9. Handle Test Data Separately

Do not routinely copy an enterprise production database, including its data, to a developer workstation.

Recommended flow:

```text
Enterprise
   │
   ├── schema      → DACPAC
   │
   └── data
          ↓
     sanitized / synthetic
          ↓
     seed-data.sql
```

Example seed data:

```sql
INSERT INTO ReferenceData.dbo.Currency
    (CurrencyCode, CurrencyName)
VALUES
    ('USD', 'US Dollar'),
    ('EUR', 'Euro'),
    ('GBP', 'British Pound');

INSERT INTO Trading.dbo.Account
    (AccountId, AccountName)
VALUES
    (1001, 'TEST_ACCOUNT_1'),
    (1002, 'TEST_ACCOUNT_2');
```

Seed enough representative data to exercise:

```text
SELECT
INSERT
UPDATE
DELETE
MERGE
stored procedures
foreign keys
transactions
deadlocks/concurrency behavior
```

For sensitive enterprise systems, synthetic data is generally the preferred local-development option. If production-derived data is needed, sanitize/mask it before distribution.

---

## DACPAC vs. Backup/Restore

A second legitimate approach is native SQL Server backup/restore:

```text
Enterprise DB
     ↓
BACKUP DATABASE
     ↓
*.bak
     ↓
Podman SQL Server
     ↓
RESTORE DATABASE
```

This is highly faithful at the database level because it brings across schema, data, indexes, statistics, database permissions, and database settings.

However, for developer Podman environments, schema-only DACPAC plus controlled seed data is usually cleaner.

| Method | Schema fidelity | Data | Automation | Recommendation |
|---|---:|---:|---:|---|
| **DACPAC + seed** | ★★★★★ | Controlled | ★★★★★ | **Best default** |
| Backup/restore | ★★★★★ | Everything | ★★★★ | Strong for controlled integration/UAT |
| BACPAC | ★★★★ | Yes | ★★★ | Not the first choice here |
| SSMS Generate Scripts | ★★★★ | Optional | ★★ | Fine for one-off use |
| Hand-written CREATE scripts | ★★ | No | ★★★ | Avoid as the primary clone mechanism |

### Recommended Choice

For a developer Podman environment:

> **DACPAC + synthetic/sanitized seed data**

For a controlled shared integration/UAT environment where production-like data is required:

> **masked/sanitized backup + restore**

---

## 10. Make the Environment One-Command Reproducible

The ideal developer experience is a command such as:

```bash
./local-env reset
```

which performs:

```text
1. podman compose down
2. remove/reinitialize the test DB volume when requested
3. podman compose up mssql
4. wait for SQL Server readiness
5. publish Trading.dacpac
6. publish Orders.dacpac
7. publish ReferenceData.dacpac
8. create local logins and permissions
9. load seed data
10. run validation
11. start Java applications
```

Suggested repository structure:

```text
project/
│
├── compose.yaml
├── services/
│   ├── service-a/
│   ├── service-b/
│   └── service-c/
│
└── local-dev/
    └── mssql/
        ├── dacpac/
        │   ├── Trading.dacpac
        │   ├── Orders.dacpac
        │   └── ReferenceData.dacpac
        │
        ├── config/
        │   └── databases.yaml
        │
        ├── server/
        │   ├── create-logins.sql
        │   └── permissions.sql
        │
        ├── seed/
        │   ├── reference-data.sql
        │   └── test-data.sql
        │
        └── scripts/
            ├── refresh-schema.sh
            ├── initialize.sh
            └── healthcheck.sh
```

---

## 11. Long-Term Enterprise Architecture: Make the Schema Source-Controlled

For the immediate problem, extracting DACPACs from the enterprise instance is practical:

```text
Enterprise SQL
      ↓
extract schema
      ↓
developer environment
```

But the more mature architecture is to make the database schema itself the source of truth in Git:

```text
                         Git
                          │
                          ▼
                SQL Database Project
                          │
                     build DACPAC
                          │
              ┌───────────┴──────────┐
              ▼                      ▼
      Enterprise SQL             Developer
         Server                  Podman SQL
```

For example:

```text
database/
├── Tables/
├── Views/
├── Stored Procedures/
├── Functions/
├── Security/
└── database.sqlproj
```

The CI build produces an immutable artifact:

```text
Trading.dacpac
```

That same DACPAC can provision:

- local Podman environments
- CI integration-test databases
- QA environments
- UAT environments
- controlled enterprise deployments

This avoids repeatedly reverse-engineering production and makes database changes reviewable, versioned, testable, and deployable through normal CI/CD controls.

---

## Recommended Implementation Sequence

1. Identify the exact enterprise SQL Server major version.
2. Identify every database your application directly or indirectly references.
3. Capture compatibility level and collation for those databases.
4. Extract one DACPAC per selected database.
5. Start a matching SQL Server Developer container under Podman.
6. Publish all DACPACs using the original database names.
7. Create local equivalents of required application logins and roles.
8. Add synthetic or sanitized seed data.
9. Validate cross-database queries and stored procedures.
10. Automate the entire process behind a single reset/provision command.
11. Longer term, migrate the database definitions into a source-controlled SQL Database Project and build DACPACs in CI.

---

## Microsoft References

- [SqlPackage overview](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage?view=sql-server-ver17)
- [SqlPackage download](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download?view=sql-server-ver17)
- [Extract a DACPAC](https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/concepts/data-tier-applications/extract-dacpac-from-database?view=sql-server-ver17)
- [SqlPackage Publish](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-publish?view=sql-server-ver17)
- [SQL Server 2022 editions and components](https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022?view=sql-server-ver17)
- [SQL Server Linux container quickstart](https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker?view=sql-server-ver17)
- [Restore a SQL Server backup in a container](https://learn.microsoft.com/en-us/sql/linux/tutorial-restore-backup-in-sql-server-container?view=sql-server-ver17)
- [Database compatibility level](https://learn.microsoft.com/en-us/sql/relational-databases/databases/view-or-change-the-compatibility-level-of-a-database?view=sql-server-ver17)
- [Collation and Unicode support](https://learn.microsoft.com/en-us/sql/relational-databases/collations/collation-and-unicode-support?view=sql-server-ver17)
- [Transfer logins and passwords between SQL Server instances](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/security/transfer-logins-passwords-between-instances)
