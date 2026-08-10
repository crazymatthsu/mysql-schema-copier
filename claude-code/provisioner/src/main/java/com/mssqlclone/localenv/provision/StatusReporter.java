package com.mssqlclone.localenv.provision;

import com.mssqlclone.localenv.config.DatabaseConfig;
import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.jdbc.ConnectionFactory;
import com.mssqlclone.localenv.podman.PodmanRunner;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.function.Consumer;

/** Human-readable snapshot of the local environment: container, instance, databases, row counts. */
public final class StatusReporter {

    private final LocalEnvConfig config;
    private final ConnectionFactory connections;
    private final Consumer<String> out;

    public StatusReporter(LocalEnvConfig config, ConnectionFactory connections, Consumer<String> out) {
        this.config = config;
        this.connections = connections;
        this.out = out;
    }

    public void report() {
        PodmanRunner podman = new PodmanRunner(config.server(), message -> {
        });
        String state = podman.containerState().orElse("absent");

        out.accept("Container");
        out.accept("  name    " + config.server().containerName());
        out.accept("  image   " + config.server().imageRef() + " (" + config.server().platform() + ")");
        out.accept("  state   " + state);
        out.accept("  port    " + config.server().hostPort() + " -> 1433");
        out.accept("  volume  " + config.server().volume());

        if (!"running".equalsIgnoreCase(state)) {
            out.accept("");
            out.accept("SQL Server is not running. Start it with: ./local-env up");
            return;
        }

        try (Connection connection = connections.asSa("master")) {
            reportInstance(connection);
            reportDatabases(connection);
        } catch (SQLException e) {
            out.accept("");
            out.accept("Could not query the instance: " + e.getMessage());
            return;
        }

        for (DatabaseConfig database : config.databases()) {
            reportDatabaseContents(database);
        }
    }

    private void reportInstance(Connection connection) throws SQLException {
        String sql = """
                SELECT
                    ProductVersion = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(64)),
                    Edition        = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(64)),
                    Collation      = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(64)),
                    HostPlatform   = (SELECT TOP (1) host_platform FROM sys.dm_os_host_info)
                """;
        try (Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery(sql)) {
            if (rows.next()) {
                out.accept("");
                out.accept("Instance");
                out.accept("  version   " + rows.getString("ProductVersion"));
                out.accept("  edition   " + rows.getString("Edition"));
                out.accept("  collation " + rows.getString("Collation"));
                out.accept("  platform  " + rows.getString("HostPlatform"));
            }
        }
    }

    private void reportDatabases(Connection connection) throws SQLException {
        String sql = """
                SELECT
                    d.name,
                    d.collation_name,
                    d.compatibility_level,
                    d.is_read_committed_snapshot_on,
                    d.state_desc,
                    SizeMb = CAST((SELECT SUM(CAST(mf.size AS BIGINT)) * 8 / 1024
                                   FROM sys.master_files AS mf
                                   WHERE mf.database_id = d.database_id) AS INT)
                FROM sys.databases AS d
                WHERE d.database_id > 4
                ORDER BY d.name
                """;
        try (Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery(sql)) {
            out.accept("");
            out.accept("Databases");
            out.accept(String.format("  %-16s %-30s %-7s %-6s %-8s %s",
                    "NAME", "COLLATION", "COMPAT", "RCSI", "STATE", "SIZE"));
            while (rows.next()) {
                out.accept(String.format("  %-16s %-30s %-7d %-6s %-8s %d MB",
                        rows.getString("name"),
                        rows.getString("collation_name"),
                        rows.getInt("compatibility_level"),
                        rows.getBoolean("is_read_committed_snapshot_on") ? "on" : "off",
                        rows.getString("state_desc"),
                        rows.getInt("SizeMb")));
            }
        }
    }

    private void reportDatabaseContents(DatabaseConfig database) {
        String objectSql = """
                SELECT
                    Tables     = SUM(CASE WHEN type = 'U'  THEN 1 ELSE 0 END),
                    Views      = SUM(CASE WHEN type = 'V'  THEN 1 ELSE 0 END),
                    Procedures = SUM(CASE WHEN type = 'P'  THEN 1 ELSE 0 END),
                    Functions  = SUM(CASE WHEN type IN ('FN','IF','TF') THEN 1 ELSE 0 END),
                    Triggers   = SUM(CASE WHEN type = 'TR' THEN 1 ELSE 0 END),
                    Sequences  = SUM(CASE WHEN type = 'SO' THEN 1 ELSE 0 END)
                FROM sys.objects
                WHERE is_ms_shipped = 0
                """;
        String rowSql = """
                SELECT
                    TableName = s.name + '.' + t.name,
                    [RowCount] = SUM(p.rows)
                FROM sys.tables AS t
                INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
                INNER JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
                GROUP BY s.name, t.name
                HAVING SUM(p.rows) > 0
                ORDER BY SUM(p.rows) DESC
                """;

        try (Connection connection = connections.asSa(database.name());
                Statement statement = connection.createStatement()) {
            out.accept("");
            out.accept(database.name());
            try (ResultSet rows = statement.executeQuery(objectSql)) {
                if (rows.next()) {
                    out.accept("  objects  tables=" + rows.getInt("Tables")
                            + " views=" + rows.getInt("Views")
                            + " procs=" + rows.getInt("Procedures")
                            + " functions=" + rows.getInt("Functions")
                            + " triggers=" + rows.getInt("Triggers")
                            + " sequences=" + rows.getInt("Sequences"));
                }
            }
            try (ResultSet rows = statement.executeQuery(rowSql)) {
                StringBuilder line = new StringBuilder("  rows     ");
                boolean any = false;
                while (rows.next()) {
                    if (any) {
                        line.append(", ");
                    }
                    line.append(rows.getString("TableName")).append('=').append(rows.getLong("RowCount"));
                    any = true;
                }
                out.accept(any ? line.toString() : "  rows     (empty)");
            }
        } catch (SQLException e) {
            out.accept("  unavailable: " + e.getMessage());
        }
    }
}
