package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.fail;

import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.jdbc.ConnectionFactory;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import org.junit.jupiter.api.BeforeAll;

/**
 * Shared setup for the integration tests.
 *
 * <p>These run against the live local clone, not an in-memory substitute: the whole point
 * of the environment is that the application meets real SQL Server semantics - collation,
 * permissions, triggers, cross-database procedure calls - before it meets them upstream.
 *
 * <p>Start the environment first:
 *
 * <pre>
 *   ./local-env reset
 *   ./gradlew :trading-app:integrationTest
 * </pre>
 */
abstract class IntegrationTestSupport {

    protected static LocalEnvConfig config;
    protected static ConnectionFactory connections;

    @BeforeAll
    static void connectToLocalEnvironment() {
        config = LocalEnvConfig.loadDefault();
        connections = ConnectionFactory.forConfig(config);

        try (Connection connection = connections.asSa("master");
                Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery("SELECT DB_ID('Orders') AS OrdersId")) {
            rows.next();
            if (rows.getObject("OrdersId") == null) {
                fail("The local databases are missing. Run ./local-env reset first.");
            }
        } catch (SQLException e) {
            fail("Could not reach the local SQL Server at " + connections.url("master")
                    + ". Start it with ./local-env up (or ./local-env reset). Cause: " + e.getMessage());
        }
    }

    /** Client order ids and execution ids must be unique across runs against the same database. */
    protected static String uniqueId(String prefix) {
        return prefix + "-" + UUID.randomUUID().toString().substring(0, 12).toUpperCase();
    }

    /** A ticker that cannot collide with the seeded universe or a concurrent test run. */
    protected static String uniqueSymbol() {
        return "IT" + UUID.randomUUID().toString().replace("-", "").substring(0, 6).toUpperCase();
    }

    protected static int instrumentId(Connection connection, String symbol, String mic) throws SQLException {
        String sql = """
                SELECT i.InstrumentId
                FROM ReferenceData.dbo.Instrument AS i
                INNER JOIN ReferenceData.dbo.Exchange AS e ON e.ExchangeId = i.ExchangeId
                WHERE i.Symbol = ? AND e.Mic = ?
                """;
        try (var statement = connection.prepareStatement(sql)) {
            statement.setString(1, symbol);
            statement.setString(2, mic);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) {
                    throw new IllegalStateException("Instrument " + symbol + "." + mic + " is not seeded");
                }
                return rows.getInt(1);
            }
        }
    }

    protected static long scalarLong(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getLong(1);
        }
    }
}
