package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.mssqlclone.localenv.config.LoginConfig;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * The security path is the part of a clone that most often ends up "close enough": the
 * application is given db_owner locally and the permission model is never exercised until
 * it reaches an environment that has one. These tests assert the local instance denies
 * exactly what the enterprise one denies.
 */
class SecurityIT extends IntegrationTestSupport {

    @Test
    @DisplayName("every configured login connects to its default database")
    void everyLoginConnects() throws SQLException {
        for (LoginConfig login : config.logins()) {
            try (Connection connection = connections.asLogin(login, login.defaultDatabase());
                    Statement statement = connection.createStatement();
                    ResultSet rows = statement.executeQuery(
                            "SELECT SUSER_SNAME() AS LoginName, DB_NAME() AS DatabaseName")) {
                rows.next();
                assertEquals(login.name(), rows.getString("LoginName"));
                assertEquals(login.defaultDatabase(), rows.getString("DatabaseName"));
            }
        }
    }

    @Test
    @DisplayName("trading_app holds the roles the configuration says it should")
    void roleMembershipMatchesConfiguration() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Trading");
                Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery("""
                        SELECT
                            IsReader   = IS_ROLEMEMBER('trading_reader'),
                            IsWriter   = IS_ROLEMEMBER('trading_writer'),
                            IsExecutor = IS_ROLEMEMBER('trading_executor'),
                            IsOwner    = IS_ROLEMEMBER('db_owner')
                        """)) {
            rows.next();
            assertEquals(1, rows.getInt("IsReader"));
            assertEquals(1, rows.getInt("IsWriter"));
            assertEquals(1, rows.getInt("IsExecutor"));
            assertEquals(0, rows.getInt("IsOwner"), "the application must not be a database owner");
        }
    }

    @Test
    @DisplayName("positions can only be changed through the procedure, never by direct DML")
    void directPositionWriteIsDenied() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Trading");
                Statement statement = connection.createStatement()) {
            SQLException denied = assertThrows(SQLException.class, () -> statement.executeUpdate(
                    "INSERT INTO dbo.Position (AccountId, InstrumentId, Quantity, AvgPrice) "
                            + "VALUES (1001, 100000, 1, 1)"));
            assertPermissionDenied(denied);
        }
    }

    @Test
    @DisplayName("orders are never hard-deleted")
    void orderDeleteIsDenied() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders");
                Statement statement = connection.createStatement()) {
            SQLException denied = assertThrows(SQLException.class,
                    () -> statement.executeUpdate("DELETE FROM dbo.[Order] WHERE OrderId = -1"));
            assertPermissionDenied(denied);
        }
    }

    @Test
    @DisplayName("the order audit journal is append-only for the application")
    void auditJournalIsAppendOnly() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders");
                Statement statement = connection.createStatement()) {
            SQLException denied = assertThrows(SQLException.class, () -> statement.executeUpdate(
                    "UPDATE audit.OrderEvent SET EventType = 'TAMPERED' WHERE EventId = -1"));
            assertPermissionDenied(denied);
        }
    }

    @Test
    @DisplayName("the reporting login can read reference data but not change it")
    void reportingLoginIsReadOnly() throws SQLException {
        try (Connection connection = connections.asLogin("report_reader", "ReferenceData");
                Statement statement = connection.createStatement()) {
            try (ResultSet rows = statement.executeQuery(
                    "SELECT COUNT(*) FROM dbo.vw_ActiveInstrument")) {
                rows.next();
                assertTrue(rows.getInt(1) > 0);
            }

            SQLException denied = assertThrows(SQLException.class, () -> statement.executeUpdate(
                    "INSERT INTO dbo.Currency (CurrencyCode, CurrencyName) VALUES ('ZZZ', N'Nope')"));
            assertPermissionDenied(denied);
        }
    }

    @Test
    @DisplayName("a cross-database procedure call needs permission in the target database too")
    void crossDatabaseExecuteIsChecked() throws SQLException {
        // report_reader is only in ref_reader/trading_reader/orders_reader/risk_reader, so the
        // Orders procedure it can see is not one it may run. Ownership chaining does not cross
        // database boundaries, which is exactly why every login is mapped into every database
        // it touches.
        try (Connection connection = connections.asLogin("report_reader", "Orders");
                Statement statement = connection.createStatement()) {
            SQLException denied = assertThrows(SQLException.class,
                    () -> statement.execute("EXEC dbo.usp_CancelOrder @OrderId = -1"));
            assertPermissionDenied(denied);
        }
    }

    private static void assertPermissionDenied(SQLException exception) {
        String message = exception.getMessage();
        assertTrue(message.contains("permission was denied") || message.contains("EXECUTE permission"),
                "expected a permission failure, got: " + message);
    }
}
