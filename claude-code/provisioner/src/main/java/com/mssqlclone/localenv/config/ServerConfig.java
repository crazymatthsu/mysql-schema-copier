package com.mssqlclone.localenv.config;

import java.util.Map;

/** Container and instance settings for the local SQL Server. */
public record ServerConfig(
        String containerName,
        String hostname,
        String image,
        String tag,
        String platform,
        String edition,
        int hostPort,
        String volume,
        String collation,
        int memoryLimitMb,
        int readyTimeoutSeconds,
        String saPasswordEnv,
        String saPasswordDefault) {

    static ServerConfig from(Map<String, Object> map) {
        return new ServerConfig(
                Yamls.optionalString(map, "containerName", "mssql"),
                Yamls.optionalString(map, "hostname", "mssql"),
                Yamls.requireString(map, "image", "server"),
                Yamls.requireString(map, "tag", "server"),
                Yamls.optionalString(map, "platform", "linux/amd64"),
                Yamls.optionalString(map, "edition", "Developer"),
                Yamls.optionalInt(map, "hostPort", 1433),
                Yamls.optionalString(map, "volume", "mssql-data"),
                Yamls.requireString(map, "collation", "server"),
                Yamls.optionalInt(map, "memoryLimitMb", 4096),
                Yamls.optionalInt(map, "readyTimeoutSeconds", 300),
                Yamls.optionalString(map, "saPasswordEnv", "MSSQL_SA_PASSWORD"),
                Yamls.optionalString(map, "saPasswordDefault", "YourStrongLocalPassword!"));
    }

    public String imageRef() {
        return image + ":" + tag;
    }

    /**
     * The sa password, from the environment when set.
     *
     * <p>The fallback is a local-only development password that is committed on purpose:
     * a container that only listens on loopback is not worth a secret-management story,
     * and hard-failing here would make {@code local-env reset} useless out of the box.
     */
    public String saPassword() {
        String fromEnv = System.getenv(saPasswordEnv);
        return fromEnv == null || fromEnv.isBlank() ? saPasswordDefault : fromEnv;
    }
}
