package com.example.mssqllocal;

public final class Main {
    private Main() {
    }

    public static void main(String[] args) throws Exception {
        int exitCode = new LocalMssqlCli(System.out, System.err).run(args);
        if (exitCode != 0) {
            System.exit(exitCode);
        }
    }
}
