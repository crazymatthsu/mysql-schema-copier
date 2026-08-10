package com.mssqlclone.localenv.jdbc;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.SQLWarning;
import java.sql.Statement;
import java.util.Comparator;
import java.util.List;
import java.util.function.Consumer;
import java.util.stream.Stream;

/** Executes .sql files, batch by batch, against an open connection. */
public final class SqlScriptRunner {

    private final Connection connection;
    private final Consumer<String> log;

    public SqlScriptRunner(Connection connection, Consumer<String> log) {
        this.connection = connection;
        this.log = log;
    }

    /** Runs every {@code *.sql} file in the directory, in filename order. */
    public int executeDirectory(Path directory) throws SQLException {
        if (!Files.isDirectory(directory)) {
            throw new IllegalArgumentException("Not a directory: " + directory);
        }
        int total = 0;
        for (Path script : listScripts(directory)) {
            total += execute(script);
        }
        return total;
    }

    public static List<Path> listScripts(Path directory) {
        try (Stream<Path> files = Files.list(directory)) {
            return files.filter(Files::isRegularFile)
                    .filter(path -> path.getFileName().toString().toLowerCase().endsWith(".sql"))
                    .sorted(Comparator.comparing(path -> path.getFileName().toString()))
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException("Could not list scripts in " + directory, e);
        }
    }

    /**
     * @return the number of batches executed
     */
    public int execute(Path script) throws SQLException {
        String sql;
        try {
            sql = Files.readString(script, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not read " + script, e);
        }

        List<String> batches = SqlBatchSplitter.split(sql);
        log.accept("  " + script.getFileName() + " (" + batches.size() + " batches)");

        int batchNumber = 0;
        for (String batch : batches) {
            batchNumber++;
            try (Statement statement = connection.createStatement()) {
                statement.execute(batch);
                drainResults(statement);
                reportWarnings(statement);
            } catch (SQLException e) {
                throw new SQLException(
                        "Failed in " + script + " (batch " + batchNumber + ", starting '"
                                + firstMeaningfulLine(batch) + "'): " + e.getMessage(),
                        e.getSQLState(), e.getErrorCode(), e);
            }
        }
        return batches.size();
    }

    /** Statements such as MERGE ... OUTPUT return result sets that must be consumed. */
    private static void drainResults(Statement statement) throws SQLException {
        while (statement.getMoreResults() || statement.getUpdateCount() != -1) {
            // Nothing to collect - stepping through the results is the point.
        }
    }

    private void reportWarnings(Statement statement) throws SQLException {
        for (SQLWarning warning = statement.getWarnings(); warning != null; warning = warning.getNextWarning()) {
            String message = warning.getMessage();
            if (message != null && !message.isBlank()) {
                log.accept("    [sql] " + message.strip());
            }
        }
    }

    private static String firstMeaningfulLine(String batch) {
        for (String line : batch.split("\n")) {
            String trimmed = line.strip();
            if (!trimmed.isEmpty() && !trimmed.startsWith("--") && !trimmed.startsWith("/*")
                    && !trimmed.startsWith("*")) {
                return trimmed.length() > 80 ? trimmed.substring(0, 77) + "..." : trimmed;
            }
        }
        return batch.strip().lines().findFirst().orElse("");
    }
}
