package com.mssqlclone.localenv.provision;

/** One validation outcome, from either a configuration check or a validation script. */
public record CheckResult(String source, String name, String detail, boolean passed) {

    public static CheckResult pass(String source, String name, String detail) {
        return new CheckResult(source, name, detail, true);
    }

    public static CheckResult fail(String source, String name, String detail) {
        return new CheckResult(source, name, detail, false);
    }
}
