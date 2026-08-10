package com.mssqlclone.localenv.jdbc;

import java.util.regex.Pattern;

/**
 * Identifier and literal handling for the dynamic SQL this tool builds.
 *
 * <p>Database, login and role names come from {@code databases.yaml} and end up inside
 * statements that cannot be parameterised ({@code CREATE DATABASE}, {@code ALTER ROLE}).
 * Everything that reaches those statements goes through here first.
 */
public final class Sql {

    private static final Pattern SAFE_IDENTIFIER = Pattern.compile("[A-Za-z_][A-Za-z0-9_$#]{0,127}");

    private Sql() {
    }

    /** Bracket-quotes an identifier after checking it against a conservative whitelist. */
    public static String quoteName(String identifier) {
        if (identifier == null || !SAFE_IDENTIFIER.matcher(identifier).matches()) {
            throw new IllegalArgumentException(
                    "Unsupported SQL identifier in configuration: '" + identifier + "'. "
                            + "Use letters, digits and underscores only.");
        }
        return "[" + identifier + "]";
    }

    /**
     * Checks a bare identifier that is used unquoted, such as a collation name.
     *
     * @return the identifier, unchanged
     */
    public static String requireIdentifier(String identifier) {
        if (identifier == null || !SAFE_IDENTIFIER.matcher(identifier).matches()) {
            throw new IllegalArgumentException(
                    "Unsupported SQL identifier in configuration: '" + identifier + "'.");
        }
        return identifier;
    }

    /** Single-quotes a string literal, doubling any embedded quotes. */
    public static String quoteLiteral(String value) {
        return "'" + value.replace("'", "''") + "'";
    }
}
