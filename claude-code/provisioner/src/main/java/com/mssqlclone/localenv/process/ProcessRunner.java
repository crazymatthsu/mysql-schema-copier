package com.mssqlclone.localenv.process;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

/** Runs external commands (podman, sqlpackage) and captures their output. */
public final class ProcessRunner {

    private ProcessRunner() {
    }

    public record Result(int exitCode, String stdout, String stderr) {

        public boolean ok() {
            return exitCode == 0;
        }

        public String combined() {
            return (stdout + "\n" + stderr).strip();
        }

        public Result requireSuccess(String what) {
            if (!ok()) {
                throw new ProcessFailedException(what + " failed (exit " + exitCode + ")\n" + combined());
            }
            return this;
        }
    }

    public static Result run(List<String> command, Path workingDirectory) {
        return run(command, workingDirectory, 600);
    }

    public static Result run(List<String> command, Path workingDirectory, long timeoutSeconds) {
        ProcessBuilder builder = new ProcessBuilder(command);
        if (workingDirectory != null) {
            builder.directory(workingDirectory.toFile());
        }

        try {
            Process process = builder.start();
            // Drain both pipes concurrently: a chatty command fills its buffer and blocks
            // otherwise, and the timeout below would never be reached.
            try (ExecutorService readers = Executors.newVirtualThreadPerTaskExecutor()) {
                Future<String> stdout = readers.submit(() -> read(process.getInputStream()));
                Future<String> stderr = readers.submit(() -> read(process.getErrorStream()));

                if (!process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                    process.destroyForcibly();
                    process.waitFor();
                    throw new ProcessFailedException(
                            "Timed out after " + timeoutSeconds + "s: " + String.join(" ", command));
                }
                return new Result(process.exitValue(), stdout.get(), stderr.get());
            }
        } catch (IOException e) {
            throw new UncheckedIOException("Could not run: " + String.join(" ", command), e);
        } catch (ExecutionException e) {
            throw new ProcessFailedException(
                    "Could not read output of: " + String.join(" ", command) + " - " + e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ProcessFailedException("Interrupted while running: " + String.join(" ", command));
        }
    }

    private static String read(java.io.InputStream stream) throws IOException {
        try (stream) {
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /** Streams the command's output straight through to the console. */
    public static int runInheritIo(List<String> command, Path workingDirectory) {
        ProcessBuilder builder = new ProcessBuilder(command).inheritIO();
        if (workingDirectory != null) {
            builder.directory(workingDirectory.toFile());
        }
        try {
            return builder.start().waitFor();
        } catch (IOException e) {
            throw new UncheckedIOException("Could not run: " + String.join(" ", command), e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ProcessFailedException("Interrupted while running: " + String.join(" ", command));
        }
    }

    public static boolean isOnPath(String executable) {
        try {
            return run(List.of("sh", "-c", "command -v " + executable), null, 15).ok();
        } catch (RuntimeException e) {
            return false;
        }
    }

    public static class ProcessFailedException extends RuntimeException {
        public ProcessFailedException(String message) {
            super(message);
        }
    }
}
