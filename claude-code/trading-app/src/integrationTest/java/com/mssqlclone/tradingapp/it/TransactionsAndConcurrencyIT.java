package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.mssqlclone.tradingapp.TradingClient;
import com.mssqlclone.tradingapp.model.Records.PlacedOrder;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Transaction and isolation behaviour.
 *
 * <p>These are the semantics that differ most between "a database" and "the same database
 * engine and settings as production": read-committed snapshot changes what a reader sees,
 * rowversion drives the application's optimistic concurrency, and a blocked writer must
 * fail the same way locally as it does upstream.
 */
class TransactionsAndConcurrencyIT extends IntegrationTestSupport {

    private static final int ACCOUNT_ID = 1003;

    @Test
    @DisplayName("rolling back the caller's transaction undoes the order and the position")
    void rollbackUndoesTheWholeChain() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "INTC", "XNAS");
            BigDecimal beforeQty = client.positionQuantity(ACCOUNT_ID, instrumentId);

            connection.setAutoCommit(false);
            long orderId;
            try {
                PlacedOrder order = client.placeOrder(uniqueId("IT-TX"), ACCOUNT_ID, instrumentId,
                        "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("23.00"));
                orderId = order.orderId();
                client.recordExecution(uniqueId("IT-EX"), orderId,
                        new BigDecimal("100"), new BigDecimal("22.50"), BigDecimal.ZERO);
                connection.rollback();
            } finally {
                connection.setAutoCommit(true);
            }

            assertTrue(client.findOrder(orderId).isEmpty(), "the order should be gone");
            assertEquals(0, client.positionQuantity(ACCOUNT_ID, instrumentId).compareTo(beforeQty),
                    "the position in Trading should be untouched");
        }
    }

    @Test
    @DisplayName("committing keeps the order, the execution and the position together")
    void commitKeepsTheWholeChain() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "NVDA", "XNAS");
            BigDecimal beforeQty = client.positionQuantity(ACCOUNT_ID, instrumentId);

            connection.setAutoCommit(false);
            long orderId;
            try {
                PlacedOrder order = client.placeOrder(uniqueId("IT-TX"), ACCOUNT_ID, instrumentId,
                        "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("128.00"));
                orderId = order.orderId();
                client.recordExecution(uniqueId("IT-EX"), orderId,
                        new BigDecimal("100"), new BigDecimal("127.00"), BigDecimal.ZERO);
                connection.commit();
            } finally {
                connection.setAutoCommit(true);
            }

            assertEquals("FILLED", client.findOrder(orderId).orElseThrow().statusCode());
            assertEquals(0, client.positionQuantity(ACCOUNT_ID, instrumentId)
                    .subtract(beforeQty).compareTo(new BigDecimal("100")));
        }
    }

    @Test
    @DisplayName("read committed snapshot lets a reader through an uncommitted write")
    void readCommittedSnapshotDoesNotBlockReaders() throws SQLException {
        try (Connection writer = connections.asLogin("refdata_app", "ReferenceData");
                Connection reader = connections.asLogin("report_reader", "ReferenceData")) {

            int instrumentId = instrumentId(writer, "GOOGL", "XNAS");
            String originalName = instrumentName(reader, instrumentId);

            writer.setAutoCommit(false);
            try {
                try (PreparedStatement update = writer.prepareStatement(
                        "UPDATE dbo.Instrument SET InstrumentName = ? WHERE InstrumentId = ?")) {
                    update.setString(1, "Uncommitted rename");
                    update.setInt(2, instrumentId);
                    update.executeUpdate();
                }

                // Without RCSI this read would block until the timeout and fail with 1222.
                try (Statement statement = reader.createStatement()) {
                    statement.execute("SET LOCK_TIMEOUT 3000");
                }
                assertEquals(originalName, instrumentName(reader, instrumentId),
                        "the reader should see the last committed version");
            } finally {
                writer.rollback();
                writer.setAutoCommit(true);
            }

            assertEquals(originalName, instrumentName(reader, instrumentId));
        }
    }

    @Test
    @DisplayName("two writers on the same row still serialise, and the loser times out")
    void concurrentWritersBlockEachOther() throws SQLException {
        try (Connection first = connections.asLogin("orders_app", "Orders");
                Connection second = connections.asLogin("orders_app", "Orders")) {

            TradingClient client = new TradingClient(first);
            int instrumentId = instrumentId(first, "TD", "XTSE");
            PlacedOrder order = client.placeOrder(uniqueId("IT-LOCK"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("79.00"));

            first.setAutoCommit(false);
            try {
                try (PreparedStatement update = first.prepareStatement(
                        "UPDATE dbo.[Order] SET Venue = 'LOCKED' WHERE OrderId = ?")) {
                    update.setLong(1, order.orderId());
                    update.executeUpdate();
                }

                try (Statement statement = second.createStatement()) {
                    statement.execute("SET LOCK_TIMEOUT 1500");
                }
                try (PreparedStatement blocked = second.prepareStatement(
                        "UPDATE dbo.[Order] SET Venue = 'OTHER' WHERE OrderId = ?")) {
                    blocked.setLong(1, order.orderId());
                    SQLException timeout = assertThrows(SQLException.class, blocked::executeUpdate);
                    assertEquals(1222, timeout.getErrorCode(),
                            "expected a lock request timeout, got: " + timeout.getMessage());
                }
            } finally {
                first.rollback();
                first.setAutoCommit(true);
            }
        }
    }

    @Test
    @DisplayName("rowversion drives optimistic concurrency the way the application expects")
    void rowVersionDetectsStaleUpdates() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "RY", "XTSE");
            PlacedOrder order = client.placeOrder(uniqueId("IT-VER"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("169.00"));

            byte[] original = rowVersion(connection, order.orderId());

            assertEquals(1, updateWithRowVersion(connection, order.orderId(), original, "FIRST"),
                    "the first update holds the current rowversion");

            byte[] current = rowVersion(connection, order.orderId());
            assertNotEquals(java.util.Arrays.toString(original), java.util.Arrays.toString(current),
                    "rowversion must change on every update");

            assertEquals(0, updateWithRowVersion(connection, order.orderId(), original, "SECOND"),
                    "an update carrying a stale rowversion must affect no rows");
        }
    }

    private static String instrumentName(Connection connection, int instrumentId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT InstrumentName FROM dbo.Instrument WHERE InstrumentId = ?")) {
            statement.setInt(1, instrumentId);
            try (ResultSet rows = statement.executeQuery()) {
                rows.next();
                return rows.getString(1);
            }
        }
    }

    private static byte[] rowVersion(Connection connection, long orderId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT RowVersion FROM dbo.[Order] WHERE OrderId = ?")) {
            statement.setLong(1, orderId);
            try (ResultSet rows = statement.executeQuery()) {
                rows.next();
                return rows.getBytes(1);
            }
        }
    }

    private static int updateWithRowVersion(Connection connection, long orderId, byte[] expected,
            String venue) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "UPDATE dbo.[Order] SET Venue = ? WHERE OrderId = ? AND RowVersion = ?")) {
            statement.setString(1, venue);
            statement.setLong(2, orderId);
            statement.setBytes(3, expected);
            return statement.executeUpdate();
        }
    }
}
