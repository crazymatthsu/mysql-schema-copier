package com.mssqlclone.localenv.config;

import java.util.List;
import java.util.Map;

/**
 * A login mapped into a database, and the database roles it joins.
 *
 * <p>The roles themselves are schema (created by the schema scripts, carried by a
 * DACPAC); only the membership is environment-specific and lives here.
 */
public record DatabaseUserConfig(String login, List<String> roles) {

    static DatabaseUserConfig from(Map<String, Object> map) {
        return new DatabaseUserConfig(
                Yamls.requireString(map, "login", "databases[].users[]"),
                Yamls.optionalStringList(map, "roles"));
    }
}
