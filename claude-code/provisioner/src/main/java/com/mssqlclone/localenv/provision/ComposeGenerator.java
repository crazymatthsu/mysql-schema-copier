package com.mssqlclone.localenv.provision;

import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.config.ServerConfig;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Generates {@code compose.yaml} from {@code databases.yaml}.
 *
 * <p>The CLI drives podman directly, so compose is optional. Generating the file instead
 * of hand-maintaining it keeps a second copy of the container settings from drifting away
 * from the one the provisioner actually uses.
 */
public final class ComposeGenerator {

    private final LocalEnvConfig config;

    public ComposeGenerator(LocalEnvConfig config) {
        this.config = config;
    }

    public Path write() {
        Path target = config.projectRoot().resolve("compose.yaml");
        try {
            Files.writeString(target, render(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not write " + target, e);
        }
        return target;
    }

    public String render() {
        ServerConfig server = config.server();
        return """
                # GENERATED FILE - do not edit.
                # Produced by: ./local-env compose-config
                # Source of truth: local-dev/mssql/config/databases.yaml
                #
                # Compose only starts the container. Schema, logins and seed data still come
                # from the provisioner:
                #
                #   podman compose up -d
                #   ./local-env provision
                #
                services:
                  mssql:
                    image: %s
                    platform: %s
                    container_name: %s
                    hostname: %s
                    ports:
                      - "%d:1433"
                    environment:
                      ACCEPT_EULA: "Y"
                      MSSQL_PID: "%s"
                      MSSQL_SA_PASSWORD: "${%s:-%s}"
                      MSSQL_COLLATION: "%s"
                      MSSQL_AGENT_ENABLED: "false"
                      TZ: "UTC"
                    volumes:
                      - %s:/var/opt/mssql
                    healthcheck:
                      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P \\"$$MSSQL_SA_PASSWORD\\" -C -Q 'SELECT 1' -b"]
                      interval: 10s
                      timeout: 5s
                      retries: 30
                      start_period: 60s

                volumes:
                  %s:
                """
                .formatted(
                        server.imageRef(),
                        server.platform(),
                        server.containerName(),
                        server.hostname(),
                        server.hostPort(),
                        server.edition(),
                        server.saPasswordEnv(),
                        server.saPasswordDefault(),
                        server.collation(),
                        server.volume(),
                        server.volume());
    }
}
