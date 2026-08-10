package com.example.mssqllocal;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

final class SqlScriptRunner {
    private final ToolConfig config;
    private final CommandRunner commands;

    SqlScriptRunner(ToolConfig config, CommandRunner commands) {
        this.config = config;
        this.commands = commands;
    }

    void runScript(Path script) throws IOException, InterruptedException {
        String sql = expandTokens(Files.readString(script, StandardCharsets.UTF_8), config.sqlTokens());
        runSql(sql);
    }

    void runSql(String sql) throws IOException, InterruptedException {
        String expanded = expandTokens(sql, config.sqlTokens());
        List<String> command = sqlcmdCommand();
        commands.printCommand(command);
        commands.require(command, expanded);
    }

    List<Path> scripts(String relativeDir) throws IOException {
        Path dir = config.mssqlDir().resolve(relativeDir);
        if (!Files.isDirectory(dir)) {
            return List.of();
        }
        try (var stream = Files.list(dir)) {
            return stream
                    .filter(path -> path.getFileName().toString().endsWith(".sql"))
                    .sorted(Comparator.comparing(path -> path.getFileName().toString()))
                    .toList();
        }
    }

    List<Path> initScripts() throws IOException {
        List<Path> scripts = new ArrayList<>();
        scripts.addAll(scripts("server").stream()
                .filter(path -> path.getFileName().toString().startsWith("01-"))
                .toList());
        scripts.addAll(scripts("schema"));
        scripts.addAll(scripts("server").stream()
                .filter(path -> !path.getFileName().toString().startsWith("01-"))
                .toList());
        scripts.addAll(scripts("seed"));
        scripts.addAll(scripts("validation"));
        return scripts;
    }

    List<Path> seedScripts() throws IOException {
        List<Path> scripts = new ArrayList<>(scripts("seed"));
        scripts.addAll(scripts("validation"));
        return scripts;
    }

    List<Path> validationScripts() throws IOException {
        return scripts("validation");
    }

    String expandTokens(String sql, Map<String, String> tokens) {
        String expanded = sql;
        for (Map.Entry<String, String> entry : tokens.entrySet()) {
            expanded = expanded.replace("${" + entry.getKey() + "}", entry.getValue());
        }
        return expanded;
    }

    private List<String> sqlcmdCommand() throws IOException, InterruptedException {
        if (!config.sqlcmdPath().isBlank()) {
            return List.of(config.sqlcmdPath(), "-S", "localhost," + config.hostPort(),
                    "-U", "sa", "-P", config.saPassword(), "-C", "-b");
        }

        if (commands.commandExists("sqlcmd")) {
            return List.of("sqlcmd", "-S", "localhost," + config.hostPort(),
                    "-U", "sa", "-P", config.saPassword(), "-C", "-b");
        }

        String container = config.containerName();
        if (containerExecutable(container, "/opt/mssql-tools18/bin/sqlcmd")) {
            return List.of("podman", "exec", "-i", container, "/opt/mssql-tools18/bin/sqlcmd",
                    "-S", "localhost", "-U", "sa", "-P", config.saPassword(), "-C", "-b");
        }
        if (containerExecutable(container, "/opt/mssql-tools/bin/sqlcmd")) {
            return List.of("podman", "exec", "-i", container, "/opt/mssql-tools/bin/sqlcmd",
                    "-S", "localhost", "-U", "sa", "-P", config.saPassword(), "-b");
        }
        throw new IllegalStateException("sqlcmd was not found on the host or inside container " + container
                + ". Install sqlcmd locally and set MSSQL_SQLCMD_PATH, or use an image that includes sqlcmd.");
    }

    private boolean containerExecutable(String container, String path) throws IOException, InterruptedException {
        CommandRunner.CommandResult result = commands.run(List.of(
                "podman", "exec", container, "test", "-x", path
        ));
        return result.exitCode() == 0;
    }
}
