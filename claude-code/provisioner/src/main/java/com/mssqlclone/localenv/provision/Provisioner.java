package com.mssqlclone.localenv.provision;

import com.mssqlclone.localenv.config.DatabaseConfig;
import com.mssqlclone.localenv.config.DatabaseUserConfig;
import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.config.LoginConfig;
import com.mssqlclone.localenv.jdbc.ConnectionFactory;
import com.mssqlclone.localenv.jdbc.Sql;
import com.mssqlclone.localenv.jdbc.SqlScriptRunner;
import java.nio.file.Files;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.function.Consumer;

/**
 * Turns an empty SQL Server container into the local clone described by databases.yaml.
 *
 * <p>Order matters and is not incidental:
 *
 * <ol>
 *   <li>instance settings - sp_configure values a DACPAC never carries;
 *   <li>databases - created with the enterprise collation and compatibility level;
 *   <li>logins - server-level principals, re-created locally with local-only passwords;
 *   <li>schema - per database, in the configured order, because cross-database views
 *       resolve their references at CREATE time;
 *   <li>users and role membership - the environment-specific half of security;
 *   <li>seed data - last, since it runs through the stored procedures and therefore
 *       needs every database to already exist.
 * </ol>
 */
public final class Provisioner {

    private final LocalEnvConfig config;
    private final ConnectionFactory connections;
    private final Consumer<String> log;

    public Provisioner(LocalEnvConfig config, ConnectionFactory connections, Consumer<String> log) {
        this.config = config;
        this.connections = connections;
        this.log = log;
    }

    /** Polls until the instance accepts logins, or the timeout expires. */
    public void waitUntilReady(Duration timeout) {
        Instant deadline = Instant.now().plus(timeout);
        int attempt = 0;
        SQLException lastFailure = null;

        log.accept("Waiting for SQL Server at " + connections.host() + ":" + connections.port()
                + " (timeout " + timeout.toSeconds() + "s)");

        while (Instant.now().isBefore(deadline)) {
            attempt++;
            try (Connection connection = connections.asSa("master");
                    Statement statement = connection.createStatement()) {
                statement.execute("SELECT 1");
                log.accept("SQL Server is accepting connections (attempt " + attempt + ").");
                return;
            } catch (SQLException e) {
                lastFailure = e;
                sleep(Duration.ofSeconds(3));
            }
        }
        throw new ProvisioningException("SQL Server did not become ready within " + timeout.toSeconds()
                + "s. Last error: " + (lastFailure == null ? "none" : lastFailure.getMessage())
                + "\nCheck container logs with: podman logs " + config.server().containerName());
    }

    /** Runs local-dev/mssql/server/*.sql against master. */
    public void applyServerConfiguration() {
        if (!Files.isDirectory(config.serverScriptDir())) {
            log.accept("No server script directory at " + config.serverScriptDir() + " - skipping.");
            return;
        }
        log.accept("Applying instance configuration");
        withSa("master", connection -> new SqlScriptRunner(connection, log)
                .executeDirectory(config.serverScriptDir()));
    }

    public void createDatabases() {
        withSa("master", connection -> {
            for (DatabaseConfig database : config.databases()) {
                createDatabase(connection, database);
            }
            return null;
        });
    }

    private void createDatabase(Connection connection, DatabaseConfig database) throws SQLException {
        String name = Sql.quoteName(database.name());
        // A collation name is an unquotable keyword position in CREATE DATABASE, so it is
        // validated rather than escaped.
        String collation = Sql.requireIdentifier(database.collation());

        try (Statement statement = connection.createStatement()) {
            statement.execute(
                    "IF DB_ID(" + Sql.quoteLiteral(database.name()) + ") IS NULL "
                            + "EXEC('CREATE DATABASE " + name + " COLLATE " + collation + "')");

            statement.execute("ALTER DATABASE " + name + " SET COMPATIBILITY_LEVEL = "
                    + database.compatibilityLevel());

            // Collation is fixed at CREATE time; realign it when an existing database drifted.
            statement.execute("IF (SELECT collation_name FROM sys.databases WHERE name = "
                    + Sql.quoteLiteral(database.name()) + ") <> " + Sql.quoteLiteral(collation)
                    + " ALTER DATABASE " + name + " COLLATE " + collation);

            statement.execute("ALTER DATABASE " + name + " SET READ_COMMITTED_SNAPSHOT "
                    + (database.readCommittedSnapshot() ? "ON" : "OFF") + " WITH ROLLBACK IMMEDIATE");

            // Local databases never need point-in-time recovery, and SIMPLE keeps the
            // container volume from filling with transaction log.
            statement.execute("ALTER DATABASE " + name + " SET RECOVERY SIMPLE");
        }

        log.accept("Database " + database.name() + " ready (collation " + collation
                + ", compatibility level " + database.compatibilityLevel()
                + ", RCSI " + (database.readCommittedSnapshot() ? "on" : "off") + ")");
    }

    /**
     * Creates the server-level logins.
     *
     * <p>{@code CHECK_POLICY = OFF} keeps a local password from being rejected by whatever
     * policy the container inherits; these credentials never leave the developer machine.
     */
    public void createLogins() {
        withSa("master", connection -> {
            try (Statement statement = connection.createStatement()) {
                for (LoginConfig login : config.logins()) {
                    String name = Sql.quoteName(login.name());
                    String password = Sql.quoteLiteral(login.password());
                    String defaultDatabase = Sql.quoteName(login.defaultDatabase());

                    statement.execute(
                            "IF SUSER_ID(" + Sql.quoteLiteral(login.name()) + ") IS NULL "
                                    + "CREATE LOGIN " + name + " WITH PASSWORD = " + password
                                    + ", DEFAULT_DATABASE = " + defaultDatabase
                                    + ", CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF");

                    statement.execute("ALTER LOGIN " + name + " WITH PASSWORD = " + password
                            + ", DEFAULT_DATABASE = " + defaultDatabase);
                    statement.execute("ALTER LOGIN " + name + " ENABLE");

                    log.accept("Login " + login.name() + " ready (default database "
                            + login.defaultDatabase() + ")");
                }
            }
            return null;
        });
    }

    public void applySchema(DatabaseConfig database) {
        if (!Files.isDirectory(database.schemaDir())) {
            throw new ProvisioningException("Schema directory not found: " + database.schemaDir());
        }
        log.accept("Applying schema to " + database.name());
        withSa(database.name(), connection -> new SqlScriptRunner(connection, log)
                .executeDirectory(database.schemaDir()));
    }

    /**
     * Maps configured logins into the database and joins them to their roles.
     *
     * <p>This is the part a DACPAC cannot do for you: the roles and their permissions are
     * database objects and travel with the schema, but the membership is environment
     * specific, and the login the user points at only exists on this instance.
     */
    public void mapUsers(DatabaseConfig database) {
        if (database.users().isEmpty()) {
            return;
        }
        withSa(database.name(), connection -> {
            try (Statement statement = connection.createStatement()) {
                for (DatabaseUserConfig user : database.users()) {
                    String login = user.login();
                    String quoted = Sql.quoteName(login);

                    statement.execute(
                            "IF DATABASE_PRINCIPAL_ID(" + Sql.quoteLiteral(login) + ") IS NULL "
                                    + "CREATE USER " + quoted + " FOR LOGIN " + quoted);

                    // Re-point a user left orphaned by a restore or a recreated login.
                    statement.execute("ALTER USER " + quoted + " WITH LOGIN = " + quoted);

                    for (String role : user.roles()) {
                        String quotedRole = Sql.quoteName(role);
                        statement.execute(
                                "IF DATABASE_PRINCIPAL_ID(" + Sql.quoteLiteral(role) + ") IS NULL "
                                        + "THROW 60000, 'Role " + role + " does not exist in "
                                        + database.name() + " - is the schema applied?', 1");
                        statement.execute("ALTER ROLE " + quotedRole + " ADD MEMBER " + quoted);
                    }
                    log.accept("User " + login + " in " + database.name() + " -> roles " + user.roles());
                }
            }
            return null;
        });
    }

    public void seed(DatabaseConfig database) {
        if (!Files.isDirectory(database.seedDir())) {
            log.accept("No seed directory for " + database.name() + " - skipping.");
            return;
        }
        log.accept("Seeding " + database.name());
        withSa(database.name(), connection -> new SqlScriptRunner(connection, log)
                .executeDirectory(database.seedDir()));
    }

    /** Full provisioning pass. */
    public void provision(boolean includeSeed) {
        applyServerConfiguration();
        createDatabases();
        createLogins();

        for (DatabaseConfig database : config.databases()) {
            applySchema(database);
            mapUsers(database);
        }

        if (includeSeed) {
            for (DatabaseConfig database : config.databases()) {
                seed(database);
            }
        }
    }

    /** Drops the application databases, newest dependency first. */
    public void dropDatabases() {
        List<DatabaseConfig> reversed = config.databases().reversed();
        withSa("master", connection -> {
            try (Statement statement = connection.createStatement()) {
                for (DatabaseConfig database : reversed) {
                    String name = Sql.quoteName(database.name());
                    statement.execute("IF DB_ID(" + Sql.quoteLiteral(database.name()) + ") IS NOT NULL "
                            + "BEGIN "
                            + "ALTER DATABASE " + name + " SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
                            + "DROP DATABASE " + name + "; "
                            + "END");
                    log.accept("Dropped " + database.name());
                }
            }
            return null;
        });
    }

    private interface SqlAction<T> {
        T apply(Connection connection) throws SQLException;
    }

    private <T> T withSa(String database, SqlAction<T> action) {
        try (Connection connection = connections.asSa(database)) {
            return action.apply(connection);
        } catch (SQLException e) {
            throw new ProvisioningException("While working on " + database + ": " + e.getMessage(), e);
        }
    }

    private static void sleep(Duration duration) {
        try {
            Thread.sleep(duration.toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ProvisioningException("Interrupted while waiting for SQL Server", e);
        }
    }
}
