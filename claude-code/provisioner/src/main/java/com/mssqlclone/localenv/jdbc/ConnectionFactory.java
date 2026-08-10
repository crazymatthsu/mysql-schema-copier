package com.mssqlclone.localenv.jdbc;

import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.config.LoginConfig;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

/**
 * Builds JDBC connections to the local SQL Server from the same configuration the
 * container is created from, so an application can never drift from the environment it
 * is supposed to be talking to.
 *
 * <p>{@code trustServerCertificate=true} is required because the container generates a
 * self-signed certificate on first start. It is a local-only setting and deliberately not
 * something the enterprise connection string should carry.
 */
public final class ConnectionFactory {

    private final String host;
    private final int port;
    private final LocalEnvConfig config;
    private final int loginTimeoutSeconds;

    public ConnectionFactory(LocalEnvConfig config, String host, int port, int loginTimeoutSeconds) {
        this.config = config;
        this.host = host;
        this.port = port;
        this.loginTimeoutSeconds = loginTimeoutSeconds;
    }

    public static ConnectionFactory forConfig(LocalEnvConfig config) {
        return new ConnectionFactory(config, "localhost", config.server().hostPort(), 10);
    }

    public String url(String database) {
        return "jdbc:sqlserver://" + host + ":" + port
                + ";databaseName=" + database
                + ";encrypt=true"
                + ";trustServerCertificate=true"
                + ";loginTimeout=" + loginTimeoutSeconds;
    }

    /** Connects as sa - provisioning only; applications must use their own login. */
    public Connection asSa(String database) throws SQLException {
        return connect(database, "sa", config.server().saPassword(), "local-db-provisioner");
    }

    /** Connects as one of the configured application logins. */
    public Connection asLogin(LoginConfig login, String database) throws SQLException {
        return connect(database, login.name(), login.password(), "local-db-" + login.name());
    }

    public Connection asLogin(String loginName, String database) throws SQLException {
        return asLogin(config.requireLogin(loginName), database);
    }

    private Connection connect(String database, String user, String password, String applicationName)
            throws SQLException {
        Properties properties = new Properties();
        properties.setProperty("user", user);
        properties.setProperty("password", password);
        properties.setProperty("applicationName", applicationName);
        return DriverManager.getConnection(url(database), properties);
    }

    public String host() {
        return host;
    }

    public int port() {
        return port;
    }

    public LocalEnvConfig config() {
        return config;
    }
}
