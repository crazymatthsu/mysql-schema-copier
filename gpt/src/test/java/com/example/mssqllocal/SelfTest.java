package com.example.mssqllocal;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Map;

public final class SelfTest {
    private SelfTest() {
    }

    public static void main(String[] args) throws Exception {
        testDefaults();
        testSqlStringEscaping();
        testTokenExpansion();
        testHelpCommand();
        System.out.println("Self tests passed.");
    }

    private static void testDefaults() {
        ToolConfig config = new ToolConfig(Path.of("/tmp/project"), Map.of());
        assertEquals("mssql", config.containerName());
        assertEquals("1433", config.hostPort());
        assertEquals("trading_app", config.appLogin());
        assertEquals("160", config.compatibilityLevel());
    }

    private static void testSqlStringEscaping() {
        assertEquals("'abc''def'", ToolConfig.sqlString("abc'def"));
    }

    private static void testTokenExpansion() {
        ToolConfig config = new ToolConfig(Path.of("/tmp/project"), Map.of("MSSQL_APP_LOGIN", "app_user"));
        SqlScriptRunner runner = new SqlScriptRunner(config, new CommandRunner(System.out));
        String expanded = runner.expandTokens("CREATE USER [${APP_LOGIN}];", config.sqlTokens());
        assertEquals("CREATE USER [app_user];", expanded);
    }

    private static void testHelpCommand() {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        int exitCode = new LocalMssqlCli(new PrintStream(out), System.err).run(new String[]{"help"});
        assertEquals(0, exitCode);
        String output = out.toString(StandardCharsets.UTF_8);
        if (!output.contains("publish-dacpacs")) {
            throw new AssertionError("help output should mention publish-dacpacs");
        }
    }

    private static void assertEquals(Object expected, Object actual) {
        if (!expected.equals(actual)) {
            throw new AssertionError("expected <" + expected + "> but got <" + actual + ">");
        }
    }
}
