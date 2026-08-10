package com.mssqlclone.localenv.cli;

import com.mssqlclone.localenv.config.ConfigException;
import com.mssqlclone.localenv.config.DatabaseConfig;
import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.jdbc.ConnectionFactory;
import com.mssqlclone.localenv.jdbc.ResultSetPrinter;
import com.mssqlclone.localenv.jdbc.SqlBatchSplitter;
import com.mssqlclone.localenv.podman.PodmanRunner;
import com.mssqlclone.localenv.process.ProcessRunner;
import com.mssqlclone.localenv.provision.CheckResult;
import com.mssqlclone.localenv.provision.ComposeGenerator;
import com.mssqlclone.localenv.provision.DacpacTool;
import com.mssqlclone.localenv.provision.Provisioner;
import com.mssqlclone.localenv.provision.ProvisioningException;
import com.mssqlclone.localenv.provision.StatusReporter;
import com.mssqlclone.localenv.provision.Validator;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.Callable;
import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.ParentCommand;

/**
 * Command line entry point for the local SQL Server clone.
 *
 * <p>Everything the environment needs is one command away:
 *
 * <pre>
 *   ./local-env reset      container + schema + logins + seed + validation
 *   ./local-env validate   prove the clone still matches the configuration
 *   ./local-env status     what is actually running right now
 * </pre>
 */
@Command(
        name = "local-db",
        mixinStandardHelpOptions = true,
        version = "local-db 0.1.0",
        description = "Provision and validate a local SQL Server clone running under Podman.",
        subcommands = {
            LocalDbCli.Up.class,
            LocalDbCli.Down.class,
            LocalDbCli.Wait.class,
            LocalDbCli.Provision.class,
            LocalDbCli.Schema.class,
            LocalDbCli.Seed.class,
            LocalDbCli.Validate.class,
            LocalDbCli.Status.class,
            LocalDbCli.Reset.class,
            LocalDbCli.Sql.class,
            LocalDbCli.Logs.class,
            LocalDbCli.ComposeConfig.class,
            LocalDbCli.DacpacExtract.class,
            LocalDbCli.DacpacPublish.class
        })
public final class LocalDbCli implements Callable<Integer> {

    @Option(names = {"-c", "--config"},
            description = "Path to databases.yaml (default: ${DEFAULT-VALUE})")
    Path configFile = Path.of(LocalEnvConfig.DEFAULT_CONFIG_PATH);

    @Option(names = "--host", description = "SQL Server host (default: ${DEFAULT-VALUE})")
    String host = "localhost";

    @Option(names = "--port", description = "SQL Server port; defaults to the configured host port")
    Integer port;

    @Option(names = {"-q", "--quiet"}, description = "Only print warnings and results")
    boolean quiet;

    private LocalEnvConfig cachedConfig;

    LocalEnvConfig config() {
        if (cachedConfig == null) {
            cachedConfig = LocalEnvConfig.load(configFile);
        }
        return cachedConfig;
    }

    ConnectionFactory connections() {
        LocalEnvConfig config = config();
        return new ConnectionFactory(config, host, port == null ? config.server().hostPort() : port, 10);
    }

    void log(String message) {
        if (!quiet) {
            System.out.println(message);
        }
    }

    void print(String message) {
        System.out.println(message);
    }

    @Override
    public Integer call() {
        new CommandLine(this).usage(System.out);
        return 0;
    }

    public static void main(String[] args) {
        LocalDbCli cli = new LocalDbCli();
        int exitCode = new CommandLine(cli)
                .setExecutionExceptionHandler((exception, commandLine, parseResult) -> {
                    if (exception instanceof ConfigException
                            || exception instanceof ProvisioningException
                            || exception instanceof ProcessRunner.ProcessFailedException
                            || exception instanceof IllegalArgumentException) {
                        System.err.println();
                        System.err.println("error: " + exception.getMessage());
                        return 1;
                    }
                    exception.printStackTrace(System.err);
                    return 1;
                })
                .execute(args);
        System.exit(exitCode);
    }

    /** Shared plumbing for the subcommands. */
    abstract static class Base implements Callable<Integer> {

        @ParentCommand
        LocalDbCli parent;

        LocalEnvConfig config() {
            return parent.config();
        }

        ConnectionFactory connections() {
            return parent.connections();
        }

        PodmanRunner podman() {
            return new PodmanRunner(config().server(), parent::log);
        }

        Provisioner provisioner() {
            return new Provisioner(config(), connections(), parent::log);
        }

        void requirePodman() {
            if (!podman().podmanAvailable()) {
                throw new ProvisioningException(
                        "podman was not found. Install Podman and start a machine first:\n"
                                + "  podman machine init && podman machine start");
            }
        }

        void waitUntilReady() {
            provisioner().waitUntilReady(Duration.ofSeconds(config().server().readyTimeoutSeconds()));
        }
    }

    @Command(name = "up", description = "Start the SQL Server container, creating it if needed.")
    static class Up extends Base {

        @Option(names = "--no-wait", description = "Return as soon as the container is started")
        boolean noWait;

        @Override
        public Integer call() {
            requirePodman();
            podman().up();
            if (!noWait) {
                waitUntilReady();
            }
            return 0;
        }
    }

    @Command(name = "down", description = "Stop and remove the container. Database files survive "
            + "unless --purge is given.")
    static class Down extends Base {

        @Option(names = "--purge",
                description = "Also delete the data volume - every local database is destroyed")
        boolean purge;

        @Override
        public Integer call() {
            requirePodman();
            if (purge) {
                parent.print("Removing container " + config().server().containerName()
                        + " AND volume " + config().server().volume()
                        + " - all local database files will be deleted.");
            }
            podman().remove(purge);
            return 0;
        }
    }

    @Command(name = "wait", description = "Block until the instance accepts connections.")
    static class Wait extends Base {

        @Option(names = "--timeout", description = "Seconds to wait; defaults to the configured value")
        Integer timeoutSeconds;

        @Override
        public Integer call() {
            provisioner().waitUntilReady(Duration.ofSeconds(
                    timeoutSeconds == null ? config().server().readyTimeoutSeconds() : timeoutSeconds));
            return 0;
        }
    }

    @Command(name = "provision",
            description = "Apply instance settings, databases, logins, schema, users and seed data.")
    static class Provision extends Base {

        @Option(names = "--skip-seed", description = "Stop after schema and security")
        boolean skipSeed;

        @Override
        public Integer call() {
            provisioner().provision(!skipSeed);
            parent.print("");
            parent.print("Provisioned: " + config().databases().stream().map(DatabaseConfig::name).toList());
            return 0;
        }
    }

    @Command(name = "schema", description = "Apply schema scripts (and role membership) only.")
    static class Schema extends Base {

        @Option(names = {"-d", "--database"}, description = "Limit to one database")
        String database;

        @Override
        public Integer call() {
            Provisioner provisioner = provisioner();
            provisioner.createDatabases();
            provisioner.createLogins();
            for (DatabaseConfig databaseConfig : selected(database)) {
                provisioner.applySchema(databaseConfig);
                provisioner.mapUsers(databaseConfig);
            }
            return 0;
        }

        private List<DatabaseConfig> selected(String name) {
            return name == null ? config().databases() : List.of(config().requireDatabase(name));
        }
    }

    @Command(name = "seed", description = "Load seed data.")
    static class Seed extends Base {

        @Option(names = {"-d", "--database"}, description = "Limit to one database")
        String database;

        @Override
        public Integer call() {
            Provisioner provisioner = provisioner();
            List<DatabaseConfig> databases = database == null
                    ? config().databases()
                    : List.of(config().requireDatabase(database));
            for (DatabaseConfig databaseConfig : databases) {
                provisioner.seed(databaseConfig);
            }
            return 0;
        }
    }

    @Command(name = "validate", description = "Check the clone against the configuration and the "
            + "validation scripts.")
    static class Validate extends Base {

        @Override
        public Integer call() {
            List<CheckResult> results = new Validator(config(), connections()).validate();
            boolean ok = Validator.report(results, parent::print);
            return ok ? 0 : 1;
        }
    }

    @Command(name = "status", description = "Show container, instance and database state.")
    static class Status extends Base {

        @Override
        public Integer call() {
            new StatusReporter(config(), connections(), parent::print).report();
            return 0;
        }
    }

    @Command(name = "reset",
            description = "Recreate the environment from scratch: drop the application databases, "
                    + "reprovision, seed and validate.")
    static class Reset extends Base {

        @Option(names = "--purge",
                description = "Recreate the container and its volume as well (slowest, most thorough)")
        boolean purge;

        @Option(names = "--skip-seed", description = "Stop after schema and security")
        boolean skipSeed;

        @Option(names = "--skip-validate", description = "Do not run validation at the end")
        boolean skipValidate;

        @Override
        public Integer call() {
            requirePodman();
            PodmanRunner podman = podman();

            if (purge) {
                parent.print("Recreating container and volume - every local database will be rebuilt.");
                podman.remove(true);
            }

            podman.up();
            waitUntilReady();

            Provisioner provisioner = provisioner();
            if (!purge) {
                parent.print("Dropping application databases: "
                        + config().databases().stream().map(DatabaseConfig::name).toList());
                provisioner.dropDatabases();
            }

            provisioner.provision(!skipSeed);

            if (skipValidate) {
                return 0;
            }
            parent.print("");
            List<CheckResult> results = new Validator(config(), connections()).validate();
            return Validator.report(results, parent::print) ? 0 : 1;
        }
    }

    @Command(name = "sql", description = "Run a query or a .sql file against one database.")
    static class Sql extends Base {

        @Option(names = {"-d", "--database"}, required = true, description = "Target database")
        String database;

        @Option(names = {"-f", "--file"}, description = "Script to execute")
        Path file;

        @Option(names = {"-e", "--execute"}, description = "Statement to execute")
        String statementText;

        @Option(names = "--login", description = "Connect as this configured login instead of sa")
        String login;

        @Override
        public Integer call() throws Exception {
            if ((file == null) == (statementText == null)) {
                throw new IllegalArgumentException("Pass exactly one of --file or --execute.");
            }

            String script = file != null
                    ? Files.readString(file, StandardCharsets.UTF_8)
                    : statementText;

            ConnectionFactory factory = connections();
            try (Connection connection = login == null
                    ? factory.asSa(database)
                    : factory.asLogin(login, database)) {
                for (String batch : SqlBatchSplitter.split(script)) {
                    try (Statement statement = connection.createStatement()) {
                        boolean isResultSet = statement.execute(batch);
                        ResultSetPrinter.printAll(statement, isResultSet, parent::print);
                    }
                }
            } catch (SQLException e) {
                parent.print("");
                System.err.println("SQL error " + e.getErrorCode() + ": " + e.getMessage());
                return 1;
            }
            return 0;
        }
    }

    @Command(name = "logs", description = "Tail the container log.")
    static class Logs extends Base {

        @Option(names = "--tail", description = "Lines to show (default: ${DEFAULT-VALUE})")
        int tail = 80;

        @Override
        public Integer call() {
            parent.print(podman().logs(tail));
            return 0;
        }
    }

    @Command(name = "compose-config", description = "Generate compose.yaml from databases.yaml.")
    static class ComposeConfig extends Base {

        @Override
        public Integer call() {
            Path written = new ComposeGenerator(config()).write();
            parent.print("Wrote " + written);
            return 0;
        }
    }

    @Command(name = "dacpac-extract",
            description = "Extract a schema-only DACPAC from an upstream SQL Server (needs sqlpackage).")
    static class DacpacExtract extends Base {

        @Option(names = {"-d", "--database"}, required = true, description = "Database to extract")
        String database;

        @Option(names = "--source-server", description = "Upstream server; defaults to the configured value")
        String sourceServer;

        @Option(names = "--integrated", description = "Use Integrated Security instead of a SQL login")
        boolean integrated;

        @Option(names = "--user", description = "SQL login on the upstream server")
        String user;

        @Option(names = "--password", arity = "0..1", interactive = true,
                description = "Password for --user (prompted when omitted)")
        String password;

        @Override
        public Integer call() {
            String server = sourceServer != null ? sourceServer : config().dacpac().sourceServer();
            if (server == null || server.isBlank()) {
                throw new IllegalArgumentException(
                        "No source server. Pass --source-server or set dacpac.sourceServer in databases.yaml.");
            }
            if (!integrated && (user == null || password == null)) {
                throw new IllegalArgumentException("Pass --integrated, or both --user and --password.");
            }
            Path written = new DacpacTool(config(), parent::print)
                    .extract(database, server, integrated, user, password);
            parent.print("Wrote " + written);
            return 0;
        }
    }

    @Command(name = "dacpac-publish",
            description = "Publish a DACPAC into the local container (needs sqlpackage).")
    static class DacpacPublish extends Base {

        @Option(names = {"-d", "--database"}, required = true, description = "Target database")
        String database;

        @Option(names = {"-f", "--file"}, description = "DACPAC to publish; defaults to <database>.dacpac")
        Path file;

        @Override
        public Integer call() {
            DatabaseConfig databaseConfig = config().requireDatabase(database);
            ConnectionFactory factory = connections();
            new DacpacTool(config(), parent::print).publish(
                    databaseConfig, file, factory.host(), factory.port(), config().server().saPassword());
            return 0;
        }
    }
}
