package com.example.mssqllocal;

import java.nio.file.Path;
import java.util.Map;

final class ToolConfig {
    private final Path projectDir;
    private final Map<String, String> env;

    ToolConfig(Path projectDir, Map<String, String> env) {
        this.projectDir = projectDir;
        this.env = env;
    }

    Path projectDir() {
        return projectDir;
    }

    Path mssqlDir() {
        return projectDir.resolve("local-dev").resolve("mssql");
    }

    String containerName() {
        return env("MSSQL_CONTAINER", "mssql");
    }

    String image() {
        return env("MSSQL_IMAGE", "mcr.microsoft.com/mssql/server:2022-latest");
    }

    String volumeName() {
        return env("MSSQL_VOLUME", "mssql-data");
    }

    String hostPort() {
        return env("MSSQL_HOST_PORT", "1433");
    }

    String platform() {
        return env.getOrDefault("MSSQL_PLATFORM", "").trim();
    }

    String saPassword() {
        return env("MSSQL_SA_PASSWORD", "YourStrongLocalPassword!");
    }

    String appLogin() {
        return env("MSSQL_APP_LOGIN", "trading_app");
    }

    String appPassword() {
        return env("MSSQL_APP_PASSWORD", "LocalTestPassword123!");
    }

    String compatibilityLevel() {
        return env("MSSQL_COMPATIBILITY_LEVEL", "160");
    }

    String collation() {
        return env("MSSQL_COLLATION", "SQL_Latin1_General_CP1_CI_AS");
    }

    String sqlcmdPath() {
        return env.getOrDefault("MSSQL_SQLCMD_PATH", "").trim();
    }

    String sqlpackagePath() {
        return env("SQLPACKAGE_PATH", "sqlpackage");
    }

    String targetConnectionString(String databaseName) {
        return "Server=localhost," + hostPort()
                + ";Database=" + databaseName
                + ";User ID=sa;Password=" + saPassword()
                + ";Encrypt=true;TrustServerCertificate=true";
    }

    Map<String, String> sqlTokens() {
        return Map.of(
                "APP_LOGIN", appLogin(),
                "APP_PASSWORD_SQL", sqlString(appPassword()),
                "COMPATIBILITY_LEVEL", compatibilityLevel(),
                "COLLATION", collation()
        );
    }

    String summary() {
        return """
                Local MSSQL configuration
                  projectDir: %s
                  container:  %s
                  image:      %s
                  platform:   %s
                  volume:     %s
                  endpoint:   localhost,%s
                  app login:  %s
                  collation:  %s
                  compat:     %s
                """.formatted(projectDir, containerName(), image(),
                platform().isBlank() ? "podman default" : platform(),
                volumeName(), hostPort(),
                appLogin(), collation(), compatibilityLevel());
    }

    private String env(String name, String defaultValue) {
        String value = env.get(name);
        return value == null || value.isBlank() ? defaultValue : value;
    }

    static String sqlString(String value) {
        return "'" + value.replace("'", "''") + "'";
    }
}
