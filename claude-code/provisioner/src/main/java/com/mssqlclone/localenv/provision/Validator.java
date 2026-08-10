package com.mssqlclone.localenv.provision;

import com.mssqlclone.localenv.config.DatabaseConfig;
import com.mssqlclone.localenv.config.DatabaseUserConfig;
import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.config.LoginConfig;
import com.mssqlclone.localenv.jdbc.ConnectionFactory;
import com.mssqlclone.localenv.jdbc.Sql;
import com.mssqlclone.localenv.jdbc.SqlBatchSplitter;
import com.mssqlclone.localenv.jdbc.SqlScriptRunner;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Proves the local clone actually behaves like the instance it was cloned from.
 *
 * <p>Two kinds of check run here. Settings that live in the configuration - collation,
 * compatibility level, snapshot isolation, logins, role membership - are asserted against
 * {@code databases.yaml}, because only the configuration knows what they are supposed to
 * be. Everything about the schema and the data is asserted by the SQL files in
 * {@code local-dev/mssql/validate}, which any developer can extend without touching Java.
 */
public final class Validator {

    private final LocalEnvConfig config;
    private final ConnectionFactory connections;

    public Validator(LocalEnvConfig config, ConnectionFactory connections) {
        this.config = config;
        this.connections = connections;
    }

    public List<CheckResult> validate() {
        List<CheckResult> results = new ArrayList<>();
        results.addAll(checkDatabaseSettings());
        results.addAll(checkLoginConnectivity());
        results.addAll(checkRoleMembership());
        results.addAll(runValidationScripts());
        return results;
    }

    /** Collation, compatibility level and snapshot isolation, against the configuration. */
    private List<CheckResult> checkDatabaseSettings() {
        List<CheckResult> results = new ArrayList<>();
        String sql = """
                SELECT
                    d.name,
                    d.collation_name,
                    d.compatibility_level,
                    d.is_read_committed_snapshot_on,
                    d.state_desc
                FROM sys.databases AS d
                WHERE d.name = ?
                """;

        try (Connection connection = connections.asSa("master")) {
            for (DatabaseConfig database : config.databases()) {
                try (PreparedStatement statement = connection.prepareStatement(sql)) {
                    statement.setString(1, database.name());
                    try (ResultSet rows = statement.executeQuery()) {
                        if (!rows.next()) {
                            results.add(CheckResult.fail("config", "Database " + database.name() + " exists",
                                    "not found on the instance"));
                            continue;
                        }
                        String collation = rows.getString("collation_name");
                        int compatibility = rows.getInt("compatibility_level");
                        boolean rcsi = rows.getBoolean("is_read_committed_snapshot_on");
                        String state = rows.getString("state_desc");

                        boolean ok = database.collation().equalsIgnoreCase(collation)
                                && database.compatibilityLevel() == compatibility
                                && database.readCommittedSnapshot() == rcsi
                                && "ONLINE".equalsIgnoreCase(state);

                        results.add(new CheckResult("config",
                                "Database settings match configuration: " + database.name(),
                                "collation=" + collation + " compat=" + compatibility
                                        + " rcsi=" + rcsi + " state=" + state,
                                ok));
                    }
                }
            }
        } catch (SQLException e) {
            results.add(CheckResult.fail("config", "Read sys.databases", e.getMessage()));
        }
        return results;
    }

    /** Every configured login must be able to connect - password, state and default database. */
    private List<CheckResult> checkLoginConnectivity() {
        List<CheckResult> results = new ArrayList<>();
        for (LoginConfig login : config.logins()) {
            try (Connection connection = connections.asLogin(login, login.defaultDatabase());
                    Statement statement = connection.createStatement();
                    ResultSet rows = statement.executeQuery(
                            "SELECT SUSER_SNAME() AS LoginName, DB_NAME() AS DatabaseName")) {
                rows.next();
                results.add(CheckResult.pass("config", "Login connects: " + login.name(),
                        rows.getString("LoginName") + " -> " + rows.getString("DatabaseName")));
            } catch (SQLException e) {
                results.add(CheckResult.fail("config", "Login connects: " + login.name(), e.getMessage()));
            }
        }
        return results;
    }

    /** Role membership is the environment-specific half of security, so it is asserted here. */
    private List<CheckResult> checkRoleMembership() {
        List<CheckResult> results = new ArrayList<>();
        String sql = """
                SELECT r.name AS RoleName
                FROM sys.database_role_members AS drm
                INNER JOIN sys.database_principals AS r ON r.principal_id = drm.role_principal_id
                INNER JOIN sys.database_principals AS m ON m.principal_id = drm.member_principal_id
                WHERE m.name = ?
                """;

        for (DatabaseConfig database : config.databases()) {
            try (Connection connection = connections.asSa(database.name())) {
                for (DatabaseUserConfig user : database.users()) {
                    List<String> actual = new ArrayList<>();
                    try (PreparedStatement statement = connection.prepareStatement(sql)) {
                        statement.setString(1, user.login());
                        try (ResultSet rows = statement.executeQuery()) {
                            while (rows.next()) {
                                actual.add(rows.getString("RoleName"));
                            }
                        }
                    }
                    boolean ok = actual.containsAll(user.roles());
                    results.add(new CheckResult("config",
                            "Role membership " + database.name() + "." + user.login(),
                            "expected=" + user.roles() + " actual=" + actual,
                            ok));
                }
            } catch (SQLException e) {
                results.add(CheckResult.fail("config",
                        "Role membership in " + database.name(), e.getMessage()));
            }
        }
        return results;
    }

    /**
     * Runs every script in the validation directory against master.
     *
     * <p>A script may return any number of result sets; only those carrying the
     * {@code (CheckName, Detail, Passed)} contract are collected, so a script is free to
     * EXEC a procedure that emits its own output.
     */
    private List<CheckResult> runValidationScripts() {
        List<CheckResult> results = new ArrayList<>();
        Path directory = config.validationScriptDir();
        if (!Files.isDirectory(directory)) {
            results.add(CheckResult.fail("script", "Validation directory", directory + " not found"));
            return results;
        }

        try (Connection connection = connections.asSa("master")) {
            for (Path script : SqlScriptRunner.listScripts(directory)) {
                String source = script.getFileName().toString();
                try {
                    results.addAll(runValidationScript(connection, script, source));
                } catch (SQLException e) {
                    results.add(CheckResult.fail(source, "Script executed", e.getMessage()));
                }
            }
        } catch (SQLException e) {
            results.add(CheckResult.fail("script", "Connect as sa", e.getMessage()));
        }
        return results;
    }

    private List<CheckResult> runValidationScript(Connection connection, Path script, String source)
            throws SQLException {
        String sql;
        try {
            sql = Files.readString(script, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not read " + script, e);
        }

        List<CheckResult> results = new ArrayList<>();
        for (String batch : SqlBatchSplitter.split(sql)) {
            try (Statement statement = connection.createStatement()) {
                boolean hasResultSet = statement.execute(batch);
                while (true) {
                    if (hasResultSet) {
                        try (ResultSet rows = statement.getResultSet()) {
                            collectContractRows(rows, source, results);
                        }
                    } else if (statement.getUpdateCount() == -1) {
                        break;
                    }
                    hasResultSet = statement.getMoreResults();
                }
            }
        }
        return results;
    }

    private static void collectContractRows(ResultSet rows, String source, List<CheckResult> results)
            throws SQLException {
        ResultSetMetaData metaData = rows.getMetaData();
        int nameColumn = 0;
        int detailColumn = 0;
        int passedColumn = 0;

        for (int i = 1; i <= metaData.getColumnCount(); i++) {
            String label = metaData.getColumnLabel(i).toLowerCase(Locale.ROOT);
            switch (label) {
                case "checkname" -> nameColumn = i;
                case "detail" -> detailColumn = i;
                case "passed" -> passedColumn = i;
                default -> {
                    // Result sets emitted by procedures under test are ignored.
                }
            }
        }
        if (nameColumn == 0 || passedColumn == 0) {
            return;
        }

        while (rows.next()) {
            String name = rows.getString(nameColumn);
            String detail = detailColumn == 0 ? null : rows.getString(detailColumn);
            boolean passed = rows.getBoolean(passedColumn);
            results.add(new CheckResult(source, name, detail, passed));
        }
    }

    /** Renders results as a table and returns true when everything passed. */
    public static boolean report(List<CheckResult> results, java.util.function.Consumer<String> out) {
        int width = results.stream().mapToInt(r -> r.name().length()).max().orElse(20);
        width = Math.min(Math.max(width, 20), 80);

        String currentSource = null;
        for (CheckResult result : results) {
            if (!result.source().equals(currentSource)) {
                currentSource = result.source();
                out.accept("");
                out.accept("[" + currentSource + "]");
            }
            String detail = result.detail() == null || result.detail().isBlank()
                    ? "" : "  " + result.detail();
            out.accept(String.format("  %-4s %-" + width + "s%s",
                    result.passed() ? "PASS" : "FAIL", result.name(), detail));
        }

        long failed = results.stream().filter(r -> !r.passed()).count();
        out.accept("");
        out.accept(results.size() + " checks, " + (results.size() - failed) + " passed, " + failed + " failed");
        return failed == 0;
    }

    /** Convenience for callers that only need a single ad-hoc statement. */
    public static void execute(Connection connection, String statementText) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            statement.execute(statementText);
        }
    }

    /** Exposed so the CLI can name the databases it validated. */
    public List<String> databaseNames() {
        return config.databases().stream().map(DatabaseConfig::name).map(Sql::requireIdentifier).toList();
    }
}
