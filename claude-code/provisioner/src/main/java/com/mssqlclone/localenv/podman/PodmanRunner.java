package com.mssqlclone.localenv.podman;

import com.mssqlclone.localenv.config.ServerConfig;
import com.mssqlclone.localenv.process.ProcessRunner;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.function.Consumer;

/**
 * Container lifecycle for the local SQL Server, driven straight from {@code databases.yaml}.
 *
 * <p>Plain {@code podman} rather than {@code podman compose}: the arguments then come from
 * one source of truth, and the environment works on a machine that has podman but no
 * compose provider. {@code local-db compose-config} generates an equivalent compose.yaml
 * for teams that prefer it.
 */
public final class PodmanRunner {

    private final ServerConfig server;
    private final Consumer<String> log;

    public PodmanRunner(ServerConfig server, Consumer<String> log) {
        this.server = server;
        this.log = log;
    }

    public boolean podmanAvailable() {
        return ProcessRunner.run(List.of("podman", "--version"), null, 30).ok();
    }

    public Optional<String> containerState() {
        ProcessRunner.Result result = ProcessRunner.run(
                List.of("podman", "ps", "--all",
                        "--filter", "name=^" + server.containerName() + "$",
                        "--format", "{{.State}}"),
                null, 60);
        if (!result.ok()) {
            return Optional.empty();
        }
        String state = result.stdout().strip();
        return state.isEmpty() ? Optional.empty() : Optional.of(state.lines().findFirst().orElse(state));
    }

    public boolean isRunning() {
        return containerState().map("running"::equalsIgnoreCase).orElse(false);
    }

    public void ensureVolume() {
        ProcessRunner.Result exists = ProcessRunner.run(
                List.of("podman", "volume", "inspect", server.volume()), null, 60);
        if (exists.ok()) {
            return;
        }
        log.accept("Creating volume " + server.volume());
        ProcessRunner.run(List.of("podman", "volume", "create", server.volume()), null, 120)
                .requireSuccess("podman volume create");
    }

    /**
     * Starts the container, reusing it when it already exists.
     *
     * @return true when a container was started, false when one was already running
     */
    public boolean up() {
        Optional<String> state = containerState();
        if (state.isPresent()) {
            if ("running".equalsIgnoreCase(state.get())) {
                log.accept("Container " + server.containerName() + " is already running.");
                return false;
            }
            log.accept("Starting existing container " + server.containerName() + " (was " + state.get() + ")");
            ProcessRunner.run(List.of("podman", "start", server.containerName()), null, 300)
                    .requireSuccess("podman start");
            return true;
        }

        ensureVolume();
        List<String> command = new ArrayList<>(List.of(
                "podman", "run", "--detach",
                "--name", server.containerName(),
                "--hostname", server.hostname(),
                "--platform", server.platform(),
                "--publish", server.hostPort() + ":1433",
                "--memory", server.memoryLimitMb() + "m",
                "--env", "ACCEPT_EULA=Y",
                "--env", "MSSQL_PID=" + server.edition(),
                "--env", "MSSQL_SA_PASSWORD=" + server.saPassword(),
                "--env", "MSSQL_COLLATION=" + server.collation(),
                "--env", "MSSQL_AGENT_ENABLED=false",
                "--env", "TZ=UTC",
                "--volume", server.volume() + ":/var/opt/mssql",
                server.imageRef()));

        log.accept("Starting " + server.imageRef() + " as " + server.containerName()
                + " on port " + server.hostPort() + " (platform " + server.platform() + ")");
        ProcessRunner.run(command, null, 900).requireSuccess("podman run");
        return true;
    }

    public void stop() {
        if (containerState().isEmpty()) {
            log.accept("Container " + server.containerName() + " does not exist.");
            return;
        }
        log.accept("Stopping " + server.containerName());
        ProcessRunner.run(List.of("podman", "stop", "--time", "30", server.containerName()), null, 300);
    }

    public void remove(boolean purgeVolume) {
        stop();
        if (containerState().isPresent()) {
            log.accept("Removing container " + server.containerName());
            ProcessRunner.run(List.of("podman", "rm", "--force", server.containerName()), null, 300);
        }
        if (purgeVolume) {
            log.accept("Removing volume " + server.volume() + " (all local database files)");
            ProcessRunner.run(List.of("podman", "volume", "rm", "--force", server.volume()), null, 300);
        }
    }

    public String logs(int tailLines) {
        ProcessRunner.Result result = ProcessRunner.run(
                List.of("podman", "logs", "--tail", String.valueOf(tailLines), server.containerName()),
                null, 120);
        return result.combined();
    }
}
