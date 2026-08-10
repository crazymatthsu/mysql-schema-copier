package com.mssqlclone.localenv.config;

import java.util.Map;

/**
 * A server-level SQL login.
 *
 * <p>Logins are never carried across by a DACPAC - they live in master, not in the
 * database - so the local equivalents are re-created here with local-only passwords.
 */
public record LoginConfig(
        String name,
        String passwordEnv,
        String passwordDefault,
        String defaultDatabase) {

    static LoginConfig from(Map<String, Object> map) {
        String name = Yamls.requireString(map, "name", "logins[]");
        return new LoginConfig(
                name,
                Yamls.optionalString(map, "passwordEnv", name.toUpperCase() + "_PASSWORD"),
                Yamls.optionalString(map, "passwordDefault", "LocalTestPassword123!"),
                Yamls.optionalString(map, "defaultDatabase", "master"));
    }

    public String password() {
        String fromEnv = System.getenv(passwordEnv);
        return fromEnv == null || fromEnv.isBlank() ? passwordDefault : fromEnv;
    }
}
