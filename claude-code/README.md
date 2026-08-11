# Local SQL Server clone for an equities trading stack

A one-command local environment that reproduces an enterprise Microsoft SQL Server estate
inside a Podman container, so a Java application can read and write against SQL Server
locally in substantially the same way it does upstream.

It is the implementation of [docs/mssql-podman-schema-cloning.md](docs/mssql-podman-schema-cloning.md):

```
schema as source  ->  Podman SQL Server 2022 Developer  ->  synthetic seed data  ->  Java app
```

Four databases are provisioned under their real names, because the applications use
three-part names to cross between them:

| Database        | Contents                                                        |
|-----------------|-----------------------------------------------------------------|
| `ReferenceData` | currencies, countries, exchanges, instruments, price snapshots  |
| `Trading`       | accounts, traders, books, positions, cash, position history     |
| `Risk`          | pre-trade limits and the risk decision log                      |
| `Orders`        | orders, executions, and the order audit journal                 |

The dependency chain the environment has to keep working:

```
Orders.usp_PlaceOrder      ->  Risk.usp_CheckOrderRisk  ->  Trading.Position, ReferenceData.Instrument
Orders.usp_RecordExecution ->  Trading.usp_ApplyExecution
Trading.vw_PositionValuation, Risk.vw_AccountExposure  ->  ReferenceData.mkt.vw_LatestPrice
```

## Quick start

```bash
./local-env reset
```

That drops and rebuilds everything, then validates it: container, instance settings, four
databases with the right collation and compatibility level, schema, logins, database users
and role membership, ~120 seeded orders with their fills, and a validation report.

Then run the sample application and its integration tests:

```bash
./gradlew :trading-app:run
```

```bash
./gradlew :trading-app:integrationTest
```

Requirements: Podman, a JDK 21+ toolchain (Gradle provisions one if needed), and roughly
4 GB of memory for the container. `sqlpackage` is only needed for the two DACPAC commands.

> **Apple Silicon:** SQL Server images are `linux/amd64` only, and `sqlservr` does not run
> under QEMU user-mode emulation - it segfaults on startup. Podman must therefore run its
> machine on the `applehv` provider with Rosetta. See
> [Running on Apple Silicon](#running-on-apple-silicon).

## Commands

Everything goes through `./local-env`, which builds the provisioner on demand and forwards
to it. `local-dev/mssql/scripts/*.sh` are thin wrappers over the same commands, matching the
layout in the design document.

| Command | What it does |
|---|---|
| `./local-env reset [--purge]` | Rebuild from scratch and validate. `--purge` recreates the container and its volume too. |
| `./local-env up` / `down [--purge]` | Container lifecycle. `down` keeps the data volume unless `--purge`. |
| `./local-env provision [--skip-seed]` | Instance settings, databases, logins, schema, users, seed. |
| `./local-env schema [-d Orders]` | Re-apply schema scripts and role membership. |
| `./local-env seed [-d Orders]` | Load seed data. |
| `./local-env validate` | Assert the clone against the configuration and the validation scripts. |
| `./local-env status` | Container, instance, databases, object and row counts. |
| `./local-env sql -d Orders -e "SELECT ..."` | Ad-hoc query; `--login trading_app` to run as an application login. |
| `./local-env logs --tail 100` | Container log. |
| `./local-env compose-config` | Regenerate `compose.yaml` from `databases.yaml`. |
| `./local-env dacpac-extract -d Trading --source-server host` | Extract a schema-only DACPAC upstream. |
| `./local-env dacpac-publish -d Trading` | Publish a DACPAC into the local container. |

## Layout

```
claude-code/
├── local-env                       one entry point for everything
├── compose.yaml                    GENERATED from databases.yaml
├── docs/                           the design document this implements
├── local-dev/mssql/
│   ├── config/databases.yaml       single source of truth
│   ├── server/                     instance settings (sp_configure, linked-server policy)
│   ├── schema/<Database>/          tables, indexes, views, functions, procedures, triggers,
│   │                               roles and permissions - the source of truth for schema
│   ├── seed/<Database>/            01-reference-data.sql, 02-test-data.sql
│   ├── validate/                   checks that run after every provision
│   ├── scripts/                    start / reset / refresh-schema / seed / healthcheck / dacpac
│   └── dacpac/                     extracted DACPACs (git-ignored)
├── provisioner/                    Java CLI: podman, config, schema runner, validation
└── trading-app/                    sample Java application + integration tests
```

### `databases.yaml` is the single source of truth

Container arguments, database creation options, login provisioning, JDBC URLs and
`compose.yaml` are all derived from it. Change the enterprise version, collation or
compatibility level there and everything downstream follows.

```yaml
server:
  image: mcr.microsoft.com/mssql/server
  tag: 2022-latest
  collation: SQL_Latin1_General_CP1_CI_AS

databases:
  - name: ReferenceData
    collation: SQL_Latin1_General_CP1_CI_AS
    compatibilityLevel: 150
    readCommittedSnapshot: true
    users:
      - login: trading_app
        roles: [ref_reader, ref_executor]
```

Databases are provisioned in the order listed. Cross-database **views** resolve their
references at `CREATE` time, so a database must come after everything it reads:
`ReferenceData -> Trading -> Risk -> Orders`.

### Schema is source, not an artifact

`local-dev/mssql/schema` holds the object definitions as reviewable, versioned SQL - the end
state section 11 of the design document argues for. Scripts are idempotent (`CREATE OR
ALTER`, `IF OBJECT_ID(...) IS NULL`), so re-applying them is safe.

The DACPAC path is still supported for the transition: `dacpac-extract` pulls a schema-only
DACPAC from a real enterprise database, `dacpac-publish` applies one to the local container.
Neither is needed day to day, which is why `sqlpackage` is optional.

### Security is reproduced, not bypassed

The application never connects as `sa`. Each database defines `*_reader` / `*_writer` /
`*_executor` roles with the permissions the enterprise instance grants; the provisioner
creates the logins (server-level, so never carried by a DACPAC) and joins them to those
roles. The result is the same chain the application exercises upstream:

```
login -> database user -> role -> table/procedure permission
```

Consequences worth knowing:

- Positions and cash can only be changed through `Trading.dbo.usp_ApplyExecution`; direct
  DML is denied even for `trading_app`.
- `Orders.audit.OrderEvent` and `Risk.dbo.RiskCheckLog` are append-only for applications.
- Cross-database ownership chaining is off by default, so every login is mapped into every
  database it touches - that is why `trading_app` has a user in all four.

## Seeded data

Roughly 32 instruments across six venues (XNYS, XNAS, XLON, XTKS, XHKG, XTSE), six accounts,
three books, five traders, per-account risk limits with two deliberately tight
instrument-level overrides, and 120 orders with their fills.

The orders are placed through `usp_PlaceOrder` and filled through `usp_RecordExecution`
rather than inserted directly, so seeding exercises the whole cross-database chain and the
positions in `Trading` are genuinely derived from the executions. Two seeded orders are
rejected on purpose (`ODD_LOT`, `MAX_ORDER_QTY`) so both outcomes appear in the risk log.

Everything is deterministic and re-runnable: `MERGE` for reference data, `IF NOT EXISTS`
guards for generated activity.

## Validation

`./local-env validate` runs two kinds of check.

Settings that only the configuration knows - collation, compatibility level, snapshot
isolation, login connectivity, role membership - are asserted in Java against
`databases.yaml`. Everything about schema and data lives in `local-dev/mssql/validate/*.sql`
and can be extended without touching Java. A validation script returns result sets shaped
`(CheckName, Detail, Passed)`; any other result set it produces is ignored, so a script can
`EXEC` a procedure it is smoke-testing.

The shipped checks cover instance edition/version/collation, per-database settings, an object
inventory, the presence of every object the application binds to by name, cross-database
joins and procedure calls, and data integrity - including that positions in `Trading`
reconcile exactly to executions in `Orders`.

## Integration tests

`./gradlew :trading-app:integrationTest` runs against the live container (they are kept out
of `check`, so `./gradlew build` passes with nothing running). They cover the behaviours the
design document lists as worth exercising:

| Suite | Covers |
|---|---|
| `SecurityIT` | login/user/role chain, denied direct DML, append-only audit, cross-database EXECUTE |
| `ReferenceDataCrudIT` | SELECT/INSERT/UPDATE/DELETE, `MERGE` upserts, FK, CHECK and filtered-unique violations, scalar functions |
| `OrderLifecycleIT` | place, partial fill, complete fill, weighted average price, cancel, duplicate id, overfill, audit trigger |
| `CrossDatabaseIT` | fills moving positions and cash across databases, realised P&L, the documented three-part-name join, `usp_CalculateRisk` |
| `RiskLimitIT` | odd lot, max order quantity, max notional, max net position, risk log durability across a rollback |
| `TransactionsAndConcurrencyIT` | commit/rollback of the whole chain, read-committed snapshot, lock timeout on a write-write conflict, `rowversion` optimistic concurrency |

`./gradlew test` runs the unit tests, which need no database - notably the `GO` batch
splitter, the one component that could silently corrupt a schema if it got a split wrong.

## Running on Apple Silicon

SQL Server publishes `linux/amd64` images only. Podman can run them on an ARM Mac in two
ways, and only one of them works for SQL Server:

- **QEMU user-mode emulation** (what the `libkrun` machine provider uses): general binaries
  run, but `sqlservr` segfaults immediately on startup. The container log shows
  `launch_sqlservr.sh: line 28: 9 Segmentation fault (core dumped)`.
- **Rosetta** (the `applehv` machine provider): SQL Server 2022 runs normally.

To create a Rosetta-backed machine alongside an existing one:

```bash
CONTAINERS_MACHINE_PROVIDER=applehv podman machine init mssql-rosetta --cpus 4 --memory 8192 --now
```

`podman machine init --now` makes the new machine the default connection. Switch back to a
previous machine at any time:

```bash
podman system connection default podman-machine-default
```

Check which emulation a machine offers:

```bash
podman machine ssh 'ls /proc/sys/fs/binfmt_misc/'
```

On an x86-64 host (Linux, Windows, Intel Mac) none of this applies - `./local-env reset`
works directly.

## Verification status

What has been exercised on the machine this was written on:

- `./gradlew build` - both modules compile; the unit tests pass, including the eleven
  `GO`-splitter cases.
- `./local-env --help`, `status` and `compose-config` run against the real configuration.
- The `linux/amd64` SQL Server image pulls and its userland runs; `sqlservr` itself
  segfaults under that machine's QEMU emulation, so the container never reaches a listening
  state.

What that leaves unverified against a live server on this machine: the schema scripts, the
provisioning and seeding flow, the validation suite, and the integration tests. They are
written to run with `./local-env reset` followed by `./gradlew :trading-app:integrationTest`
on any x86-64 host, or on a Rosetta-backed `applehv` Podman machine - see
[Running on Apple Silicon](#running-on-apple-silicon).

## Troubleshooting

**`SQL Server did not become ready`** - `./local-env logs --tail 100`. A segfault means the
emulation problem above. `Insufficient memory` means the container needs more than
`server.memoryLimitMb`.

**Port 1433 already in use** - another SQL Server container is bound to it. Change
`server.hostPort` in `databases.yaml` and re-run `./local-env up`; the JDBC URLs follow
automatically.

**`Role ... does not exist`** during provisioning - the schema scripts have not run for that
database. `./local-env schema -d <Database>` first; role membership is applied after the
roles are created.

**Validation fails on collation or compatibility level** - the database was created before
`databases.yaml` changed. `./local-env reset` recreates it; collation is fixed at `CREATE
DATABASE` time and only partially fixable afterwards.

**Passwords** - local-only defaults live in `databases.yaml` and are overridden by the
environment variables named there (`MSSQL_SA_PASSWORD`, `TRADING_APP_PASSWORD`, ...). No
enterprise credential belongs in this repository.
