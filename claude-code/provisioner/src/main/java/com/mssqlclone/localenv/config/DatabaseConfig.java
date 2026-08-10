package com.mssqlclone.localenv.config;

import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * One application database.
 *
 * <p>Collation and compatibility level are part of environment fidelity, not cosmetics:
 * they change comparison semantics and optimizer behaviour, so they are configured
 * per database and asserted by {@code local-db validate}.
 */
public record DatabaseConfig(
        String name,
        String collation,
        int compatibilityLevel,
        boolean readCommittedSnapshot,
        Path schemaDir,
        Path seedDir,
        List<DatabaseUserConfig> users) {

    static DatabaseConfig from(Map<String, Object> map, Path projectRoot) {
        String name = Yamls.requireString(map, "name", "databases[]");
        String path = "databases." + name;

        List<DatabaseUserConfig> users = Yamls.optionalMapList(map, "users", path).stream()
                .map(DatabaseUserConfig::from)
                .toList();

        return new DatabaseConfig(
                name,
                Yamls.requireString(map, "collation", path),
                Yamls.requireInt(map, "compatibilityLevel", path),
                Yamls.optionalBoolean(map, "readCommittedSnapshot", false),
                projectRoot.resolve(Yamls.optionalString(map, "schemaDir", "local-dev/mssql/schema/" + name)),
                projectRoot.resolve(Yamls.optionalString(map, "seedDir", "local-dev/mssql/seed/" + name)),
                users);
    }
}
