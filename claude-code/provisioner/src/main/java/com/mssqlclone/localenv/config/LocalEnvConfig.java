package com.mssqlclone.localenv.config;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.yaml.snakeyaml.LoaderOptions;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.SafeConstructor;

/**
 * The whole local environment, as described by {@code local-dev/mssql/config/databases.yaml}.
 *
 * <p>Container arguments, database creation options, login provisioning and the JDBC URLs
 * used by the sample application are all derived from this one file, so there is a single
 * place to change when the enterprise instance being cloned changes.
 */
public record LocalEnvConfig(
        Path configFile,
        Path projectRoot,
        ServerConfig server,
        List<LoginConfig> logins,
        List<DatabaseConfig> databases,
        Path validationScriptDir,
        DacpacConfig dacpac) {

    public static final String DEFAULT_CONFIG_PATH = "local-dev/mssql/config/databases.yaml";

    /** Loads the configuration, resolving every relative path against the file's project root. */
    public static LocalEnvConfig load(Path configFile) {
        Path absolute = configFile.toAbsolutePath().normalize();
        if (!Files.isRegularFile(absolute)) {
            throw new ConfigException("Configuration file not found: " + absolute
                    + "\nRun from the project root, or pass --config <path>.");
        }

        Map<String, Object> root;
        try (InputStream in = Files.newInputStream(absolute)) {
            Yaml yaml = new Yaml(new SafeConstructor(new LoaderOptions()));
            root = Yamls.requireMap(yaml.load(in), "<root>");
        } catch (IOException e) {
            throw new ConfigException("Could not read " + absolute, e);
        }

        // databases.yaml lives at <root>/local-dev/mssql/config/databases.yaml.
        Path projectRoot = absolute.getParent().getParent().getParent().getParent();

        ServerConfig server = ServerConfig.from(Yamls.requireMap(root.get("server"), "server"));

        List<LoginConfig> logins = Yamls.requireMapList(root.get("logins"), "logins").stream()
                .map(LoginConfig::from)
                .toList();

        List<DatabaseConfig> databases = Yamls.requireMapList(root.get("databases"), "databases").stream()
                .map(entry -> DatabaseConfig.from(entry, projectRoot))
                .toList();

        if (databases.isEmpty()) {
            throw new ConfigException("databases: at least one database must be configured");
        }

        Map<String, Object> validation = root.containsKey("validation")
                ? Yamls.requireMap(root.get("validation"), "validation")
                : Map.of();
        Path validationDir = projectRoot.resolve(
                Yamls.optionalString(validation, "scriptDir", "local-dev/mssql/validate"));

        DacpacConfig dacpac = DacpacConfig.from(
                root.containsKey("dacpac") ? Yamls.requireMap(root.get("dacpac"), "dacpac") : Map.of(),
                projectRoot);

        LocalEnvConfig config = new LocalEnvConfig(
                absolute, projectRoot, server, logins, databases, validationDir, dacpac);
        config.verifyLoginReferences();
        return config;
    }

    public static LocalEnvConfig loadDefault() {
        return load(Path.of(DEFAULT_CONFIG_PATH));
    }

    /** A database user can only be mapped to a login the configuration actually creates. */
    private void verifyLoginReferences() {
        Map<String, LoginConfig> byName = new LinkedHashMap<>();
        for (LoginConfig login : logins) {
            byName.put(login.name(), login);
        }
        for (DatabaseConfig database : databases) {
            for (DatabaseUserConfig user : database.users()) {
                if (!byName.containsKey(user.login())) {
                    throw new ConfigException("databases." + database.name() + ".users: '" + user.login()
                            + "' is not declared under logins");
                }
            }
        }
    }

    public Optional<DatabaseConfig> database(String name) {
        return databases.stream()
                .filter(db -> db.name().equalsIgnoreCase(name))
                .findFirst();
    }

    public DatabaseConfig requireDatabase(String name) {
        return database(name).orElseThrow(() -> new ConfigException(
                "Unknown database '" + name + "'. Configured: "
                        + databases.stream().map(DatabaseConfig::name).toList()));
    }

    public Optional<LoginConfig> login(String name) {
        return logins.stream()
                .filter(login -> login.name().equalsIgnoreCase(name))
                .findFirst();
    }

    public LoginConfig requireLogin(String name) {
        return login(name).orElseThrow(() -> new ConfigException(
                "Unknown login '" + name + "'. Configured: "
                        + logins.stream().map(LoginConfig::name).toList()));
    }

    public Path serverScriptDir() {
        return projectRoot.resolve("local-dev/mssql/server");
    }
}
