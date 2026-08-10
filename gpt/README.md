# Local SQL Server Schema Copier

This folder contains a self-contained Gradle/Java implementation of the workflow described in `../docs/mssql-podman-schema-cloning.md`.

It provisions a local Microsoft SQL Server Developer container with Podman, creates enterprise-style databases, adds local logins/roles, seeds synthetic equities trading data, and validates cross-database queries.

## Layout

```text
gpt/
├── build.gradle
├── scripts/
│   └── local-env
├── src/main/java/
└── local-dev/mssql/
    ├── dacpac/
    ├── server/
    ├── schema/
    ├── seed/
    └── validation/
```

## Quick Start

```bash
cd gpt
./scripts/local-env reset
```

The default local connection is:

```text
Server=localhost,1433
User ID=sa
Password=YourStrongLocalPassword!
```

The local application login is:

```text
User ID=trading_app
Password=LocalTestPassword123!
```

Override defaults with environment variables:

```bash
MSSQL_SA_PASSWORD='AnotherStrongPassword123!' ./scripts/local-env reset
MSSQL_HOST_PORT=11433 ./scripts/local-env start
MSSQL_PLATFORM=linux/amd64 ./scripts/local-env reset
```

On Apple Silicon or other ARM64 Podman machines, the official SQL Server container may require an AMD64-capable VM/runtime. If `./scripts/local-env reset` reports a container segmentation fault, inspect `podman machine inspect` and enable a compatible AMD64 execution path before rerunning.

## Commands

```bash
./scripts/local-env help
./scripts/local-env status
./scripts/local-env start
./scripts/local-env wait
./scripts/local-env init
./scripts/local-env seed
./scripts/local-env validate
./scripts/local-env reset
./scripts/local-env reset --destroy-volume
./scripts/local-env publish-dacpacs
```

`publish-dacpacs` scans `local-dev/mssql/dacpac/*.dacpac` and publishes each file into a database named after the DACPAC file.

## Simulated Databases

The SQL assets create four local databases that preserve the enterprise-style names called out in the design doc:

- `ReferenceData`: currencies, exchanges, instrument types, and instruments.
- `Trading`: accounts, traders, portfolios, positions, and trade allocation procedure.
- `Orders`: orders, executions, order lifecycle procedure, and execution application procedure.
- `Risk`: simple risk scenarios and exposure calculation procedure.

Synthetic test data includes instruments such as `AAPL`, `MSFT`, `SPY`, `TSLA`, and `NVDA`, with seeded accounts, portfolios, orders, executions, and positions.

## Build And Self Test

```bash
cd gpt
gradle check
```

The Java self test is dependency-free and validates command parsing, config defaults, SQL asset discovery, and script token expansion.
