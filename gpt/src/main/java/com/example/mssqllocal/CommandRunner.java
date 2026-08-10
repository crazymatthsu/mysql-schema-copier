package com.example.mssqllocal;

import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;

final class CommandRunner {
    private final PrintStream out;

    CommandRunner(PrintStream out) {
        this.out = out;
    }

    CommandResult run(List<String> command) throws IOException, InterruptedException {
        return run(command, null);
    }

    CommandResult run(List<String> command, String stdin) throws IOException, InterruptedException {
        ProcessBuilder processBuilder = new ProcessBuilder(command);
        processBuilder.redirectErrorStream(true);
        Process process = processBuilder.start();
        if (stdin != null) {
            try (OutputStream input = process.getOutputStream()) {
                input.write(stdin.getBytes(StandardCharsets.UTF_8));
            }
        } else {
            process.getOutputStream().close();
        }
        String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        int exitCode = process.waitFor();
        return new CommandResult(exitCode, output);
    }

    CommandResult require(List<String> command) throws IOException, InterruptedException {
        CommandResult result = run(command);
        if (result.exitCode() != 0) {
            throw new IllegalStateException("Command failed (" + result.exitCode() + "): "
                    + printable(command) + System.lineSeparator() + result.output());
        }
        return result;
    }

    CommandResult require(List<String> command, String stdin) throws IOException, InterruptedException {
        CommandResult result = run(command, stdin);
        if (result.exitCode() != 0) {
            throw new IllegalStateException("Command failed (" + result.exitCode() + "): "
                    + printable(command) + System.lineSeparator() + result.output());
        }
        return result;
    }

    boolean commandExists(String executable) {
        try {
            CommandResult result = run(List.of("sh", "-lc", "command -v " + shellQuote(executable)));
            return result.exitCode() == 0;
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
            return false;
        } catch (IOException ignored) {
            return false;
        }
    }

    void waitFor(Duration duration) throws InterruptedException {
        Thread.sleep(duration.toMillis());
    }

    void printCommand(List<String> command) {
        out.println("$ " + printable(command));
    }

    static String printable(List<String> command) {
        return String.join(" ", command.stream().map(CommandRunner::shellQuote).toList());
    }

    private static String shellQuote(String part) {
        if (part.matches("[A-Za-z0-9_./:=,@+-]+")) {
            return part;
        }
        return "'" + part.replace("'", "'\"'\"'") + "'";
    }

    record CommandResult(int exitCode, String output) {
    }
}
