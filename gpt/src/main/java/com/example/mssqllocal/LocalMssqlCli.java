package com.example.mssqllocal;

import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class LocalMssqlCli {
    private static final Duration READY_INTERVAL = Duration.ofSeconds(2);
    private static final int READY_ATTEMPTS = 45;

    private final PrintStream out;
    private final PrintStream err;
    private final ToolConfig config;
    private final CommandRunner commands;
    private final SqlScriptRunner sqlScripts;

    LocalMssqlCli(PrintStream out, PrintStream err) {
        this.out = out;
        this.err = err;
        Path projectDir = Path.of("").toAbsolutePath().normalize();
        this.config = new ToolConfig(projectDir, System.getenv());
        this.commands = new CommandRunner(out);
        this.sqlScripts = new SqlScriptRunner(config, commands);
    }

    int run(String[] args) {
        String command = args.length == 0 ? "help" : args[0];
        try {
            switch (command) {
                case "help" -> printHelp();
                case "status" -> status();
                case "start" -> start();
                case "wait" -> waitForSqlServer();
                case "init" -> runScripts(sqlScripts.initScripts());
                case "seed" -> runScripts(sqlScripts.seedScripts());
                case "validate" -> runScripts(sqlScripts.validationScripts());
                case "reset" -> reset(Arrays.asList(args).contains("--destroy-volume"));
                case "publish-dacpacs" -> publishDacpacs();
                default -> {
                    err.println("Unknown command: " + command);
                    printHelp();
                    return 2;
                }
            }
            return 0;
        } catch (Exception exception) {
            err.println(exception.getMessage());
            return 1;
        }
    }

    private void printHelp() {
        out.println("""
                Usage: ./scripts/local-env <command>

                Commands:
                  help               Show this help.
                  status             Print config and tool/container status.
                  start              Create/start the local Podman SQL Server container.
                  wait               Wait until SQL Server accepts queries.
                  init               Create schemas, logins, seed data, and run validation.
                  seed               Re-run seed data and validation.
                  validate           Run validation queries.
                  reset              Start SQL Server, wait, and run init.
                  reset --destroy-volume
                                     Remove the container and Podman volume before reset.
                  publish-dacpacs    Publish local-dev/mssql/dacpac/*.dacpac by database name.
                """);
    }

    private void status() throws IOException, InterruptedException {
        out.print(config.summary());
        printTool("podman");
        printTool("sqlcmd");
        printTool(config.sqlpackagePath());
        if (commands.commandExists("podman")) {
            CommandRunner.CommandResult result = commands.run(List.of(
                    "podman", "container", "exists", config.containerName()
            ));
            out.println("container exists: " + (result.exitCode() == 0));
        }
    }

    private void printTool(String executable) {
        out.println("tool " + executable + ": " + (commands.commandExists(executable) ? "found" : "not found"));
    }

    private void reset(boolean destroyVolume) throws IOException, InterruptedException {
        if (destroyVolume) {
            commands.run(List.of("podman", "rm", "-f", config.containerName()));
            commands.run(List.of("podman", "volume", "rm", "-f", config.volumeName()));
        }
        start();
        waitForSqlServer();
        runScripts(sqlScripts.initScripts());
    }

    private void start() throws IOException, InterruptedException {
        commands.require(List.of("podman", "volume", "create", config.volumeName()));

        CommandRunner.CommandResult exists = commands.run(List.of(
                "podman", "container", "exists", config.containerName()
        ));
        if (exists.exitCode() == 0) {
            out.println("Starting existing container " + config.containerName());
            commands.require(List.of("podman", "start", config.containerName()));
            return;
        }

        out.println("Creating SQL Server container " + config.containerName());
        List<String> runCommand = new ArrayList<>(List.of(
                "podman", "run", "-d",
                "--name", config.containerName(),
                "--hostname", config.containerName()
        ));
        if (!config.platform().isBlank()) {
            runCommand.add("--platform");
            runCommand.add(config.platform());
        }
        runCommand.addAll(List.of(
                "-p", config.hostPort() + ":1433",
                "-e", "ACCEPT_EULA=Y",
                "-e", "MSSQL_PID=Developer",
                "-e", "MSSQL_SA_PASSWORD=" + config.saPassword(),
                "-v", config.volumeName() + ":/var/opt/mssql",
                config.image()
        ));
        commands.require(runCommand);
    }

    private void waitForSqlServer() throws IOException, InterruptedException {
        out.println("Waiting for SQL Server readiness...");
        for (int attempt = 1; attempt <= READY_ATTEMPTS; attempt++) {
            try {
                assertContainerRunning();
                sqlScripts.runSql("SELECT 1 AS Ready;\nGO\n");
                out.println("SQL Server is ready.");
                return;
            } catch (RuntimeException exception) {
                if (attempt == READY_ATTEMPTS) {
                    throw exception;
                }
                commands.waitFor(READY_INTERVAL);
            }
        }
    }

    private void assertContainerRunning() throws IOException, InterruptedException {
        CommandRunner.CommandResult running = commands.run(List.of(
                "podman", "inspect", "--format", "{{.State.Running}}", config.containerName()
        ));
        if (running.exitCode() != 0 || !running.output().trim().equals("true")) {
            CommandRunner.CommandResult logs = commands.run(List.of("podman", "logs", config.containerName()));
            throw new IllegalStateException("Container " + config.containerName()
                    + " is not running. Recent logs:" + System.lineSeparator() + logs.output());
        }
    }

    private void runScripts(List<Path> scripts) throws IOException, InterruptedException {
        if (scripts.isEmpty()) {
            out.println("No SQL scripts found.");
            return;
        }
        for (Path script : scripts) {
            out.println("Running " + config.projectDir().relativize(script));
            sqlScripts.runScript(script);
        }
    }

    private void publishDacpacs() throws IOException, InterruptedException {
        Path dacpacDir = config.mssqlDir().resolve("dacpac");
        if (!Files.isDirectory(dacpacDir)) {
            out.println("No DACPAC directory found: " + dacpacDir);
            return;
        }
        try (var stream = Files.list(dacpacDir)) {
            List<Path> dacpacs = stream
                    .filter(path -> path.getFileName().toString().endsWith(".dacpac"))
                    .sorted()
                    .toList();
            if (dacpacs.isEmpty()) {
                out.println("No DACPAC files found in " + dacpacDir);
                return;
            }
            for (Path dacpac : dacpacs) {
                String fileName = dacpac.getFileName().toString();
                String database = fileName.substring(0, fileName.length() - ".dacpac".length());
                List<String> command = List.of(
                        config.sqlpackagePath(),
                        "/Action:Publish",
                        "/SourceFile:" + dacpac.toAbsolutePath(),
                        "/TargetConnectionString:" + config.targetConnectionString(database)
                );
                commands.printCommand(command);
                commands.require(command);
            }
        }
    }
}
