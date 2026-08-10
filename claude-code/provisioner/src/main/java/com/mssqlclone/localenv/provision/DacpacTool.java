package com.mssqlclone.localenv.provision;

import com.mssqlclone.localenv.config.DatabaseConfig;
import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.process.ProcessRunner;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.function.Consumer;

/**
 * Wraps SqlPackage for the DACPAC path described in the design document.
 *
 * <p>The schema in {@code local-dev/mssql/schema} is the source of truth for this project,
 * which is the end state section 11 of the document argues for. These commands cover the
 * transition: extract the schema of a real enterprise database into a DACPAC, and publish
 * a DACPAC into the local container. Neither is required for day-to-day use, so SqlPackage
 * is not a prerequisite - it is only needed when these two commands are.
 */
public final class DacpacTool {

    private static final String INSTALL_HINT = """
            SqlPackage was not found on PATH.

            Install it with the .NET SDK:
              dotnet tool install --global microsoft.sqlpackage

            or download the platform build from
              https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download

            The rest of the local environment does not need SqlPackage: the schema is kept
            as source in local-dev/mssql/schema and applied by `./local-env provision`.""";

    private final LocalEnvConfig config;
    private final Consumer<String> log;

    public DacpacTool(LocalEnvConfig config, Consumer<String> log) {
        this.config = config;
        this.log = log;
    }

    public static boolean available() {
        return ProcessRunner.isOnPath("sqlpackage");
    }

    private static void requireAvailable() {
        if (!available()) {
            throw new ProvisioningException(INSTALL_HINT);
        }
    }

    /** Extracts a schema-only DACPAC from an upstream server. */
    public Path extract(String databaseName, String sourceServer, boolean integratedSecurity,
            String user, String password) {
        requireAvailable();
        Path output = outputFile(databaseName);

        StringBuilder connection = new StringBuilder("Server=").append(sourceServer)
                .append(";Database=").append(databaseName)
                .append(";Encrypt=true;TrustServerCertificate=false");
        if (integratedSecurity) {
            connection.append(";Integrated Security=true");
        } else {
            connection.append(";User ID=").append(user).append(";Password=").append(password);
        }

        List<String> command = List.of(
                "sqlpackage",
                "/Action:Extract",
                "/SourceConnectionString:" + connection,
                "/TargetFile:" + output,
                "/p:ExtractAllTableData=false",
                "/p:IgnoreUserLoginMappings=true",
                "/p:IgnorePermissions=false");

        log.accept("Extracting " + databaseName + " from " + sourceServer + " to " + output);
        ProcessRunner.Result result = ProcessRunner.run(command, config.projectRoot(), 3600);
        log.accept(result.combined());
        result.requireSuccess("sqlpackage /Action:Extract");
        return output;
    }

    /** Publishes a DACPAC into the local container. */
    public void publish(DatabaseConfig database, Path dacpacFile, String host, int port, String saPassword) {
        requireAvailable();
        Path file = dacpacFile != null ? dacpacFile : outputFile(database.name());
        if (!Files.isRegularFile(file)) {
            throw new ProvisioningException("DACPAC not found: " + file
                    + "\nExtract one first with: ./local-env dacpac-extract --database " + database.name());
        }

        String target = "Server=" + host + "," + port
                + ";Database=" + database.name()
                + ";User ID=sa;Password=" + saPassword
                + ";Encrypt=true;TrustServerCertificate=true";

        List<String> command = List.of(
                "sqlpackage",
                "/Action:Publish",
                "/SourceFile:" + file,
                "/TargetConnectionString:" + target,
                "/p:CreateNewDatabase=false",
                "/p:BlockOnPossibleDataLoss=true",
                // Logins and their mappings are local concerns, handled by the provisioner.
                "/p:IgnoreUserSettingsObjects=true",
                "/p:IgnoreLoginSids=true",
                "/p:DropObjectsNotInSource=false");

        log.accept("Publishing " + file + " into " + database.name());
        ProcessRunner.Result result = ProcessRunner.run(command, config.projectRoot(), 3600);
        log.accept(result.combined());
        result.requireSuccess("sqlpackage /Action:Publish");
    }

    private Path outputFile(String databaseName) {
        Path directory = config.dacpac().outputDir();
        try {
            Files.createDirectories(directory);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not create " + directory, e);
        }
        return directory.resolve(databaseName + ".dacpac");
    }
}
