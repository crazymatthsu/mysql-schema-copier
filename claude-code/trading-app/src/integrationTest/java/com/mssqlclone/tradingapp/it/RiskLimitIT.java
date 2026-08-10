package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.mssqlclone.tradingapp.TradingClient;
import com.mssqlclone.tradingapp.model.Records.PlacedOrder;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Pre-trade risk, which is the longest cross-database call in the schema:
 * Orders calls Risk, and Risk reads Trading and ReferenceData before deciding.
 */
class RiskLimitIT extends IntegrationTestSupport {

    private static final int ACCOUNT_ID = 1003;

    @Test
    @DisplayName("an odd lot is rejected before risk is even consulted")
    void oddLotIsRejected() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            // Tokyo trades in lots of 100.
            int instrumentId = instrumentId(connection, "7203", "XTKS");

            PlacedOrder order = client.placeOrder(uniqueId("IT-ODD"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("150"), "MARKET", null);

            assertEquals("REJECTED", order.statusCode());
            assertEquals("ODD_LOT", order.rejectReason());
            assertEquals(0, client.findOrder(order.orderId()).orElseThrow()
                            .leavesQty().compareTo(BigDecimal.ZERO),
                    "a rejected order must not be working");
        }
    }

    @Test
    @DisplayName("an order above the per-instrument quantity limit is rejected")
    void maxOrderQuantityIsEnforced() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            // The seed gives account 1002 a 1,000 share limit on AAPL specifically.
            int instrumentId = instrumentId(connection, "AAPL", "XNAS");

            PlacedOrder order = client.placeOrder(uniqueId("IT-MAXQ"), 1002, instrumentId,
                    "BUY", new BigDecimal("5000"), "LIMIT", new BigDecimal("100.00"));

            assertEquals("REJECTED", order.statusCode());
            assertEquals("MAX_ORDER_QTY", order.rejectReason());
        }
    }

    @Test
    @DisplayName("an order above the notional limit is rejected")
    void maxNotionalIsEnforced() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "AAPL", "XNAS");

            // Under the 1,000 share cap, but 900 * 600 = 540,000 is over the 500,000 notional cap.
            PlacedOrder order = client.placeOrder(uniqueId("IT-MAXN"), 1002, instrumentId,
                    "BUY", new BigDecimal("900"), "LIMIT", new BigDecimal("600.00"));

            assertEquals("REJECTED", order.statusCode());
            assertEquals("MAX_ORDER_NOTIONAL", order.rejectReason());
        }
    }

    @Test
    @DisplayName("a limit set against the current position blocks the next order")
    void maxNetPositionUsesTheTradingPosition() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "BA", "XNYS");

            BigDecimal current = client.positionQuantity(ACCOUNT_ID, instrumentId);
            // Allow the position to grow by 100 and no further.
            setRiskLimit(connection, ACCOUNT_ID, instrumentId, current.abs().add(new BigDecimal("100")));

            try {
                PlacedOrder allowed = client.placeOrder(uniqueId("IT-NET"), ACCOUNT_ID, instrumentId,
                        "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("155.00"));
                assertEquals("NEW", allowed.statusCode(), allowed.rejectReason());
                client.recordExecution(uniqueId("IT-EX"), allowed.orderId(),
                        new BigDecimal("100"), new BigDecimal("155.00"), BigDecimal.ZERO);

                PlacedOrder blocked = client.placeOrder(uniqueId("IT-NET"), ACCOUNT_ID, instrumentId,
                        "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("155.00"));
                assertEquals("REJECTED", blocked.statusCode());
                assertEquals("MAX_NET_POSITION", blocked.rejectReason());
            } finally {
                deactivateRiskLimit(connection, ACCOUNT_ID, instrumentId);
            }
        }
    }

    @Test
    @DisplayName("every decision is written to the risk audit log")
    void everyDecisionIsLogged() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "RIO", "XLON");
            String clOrdId = uniqueId("IT-LOG");

            client.placeOrder(clOrdId, ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("52.00"));

            try (PreparedStatement statement = connection.prepareStatement("""
                    SELECT Decision, ReasonCode, RequestedQty, Notional
                    FROM Risk.dbo.RiskCheckLog
                    WHERE ClOrdId = ?
                    """)) {
                statement.setString(1, clOrdId);
                try (ResultSet rows = statement.executeQuery()) {
                    assertTrue(rows.next(), "the pre-trade check was not logged");
                    assertEquals("APPROVED", rows.getString("Decision"));
                    assertEquals(0, rows.getBigDecimal("RequestedQty").compareTo(new BigDecimal("100")));
                    assertEquals(0, rows.getBigDecimal("Notional").compareTo(new BigDecimal("5200.00")));
                }
            }
        }
    }

    @Test
    @DisplayName("the risk log survives a rolled back order")
    void riskLogIsWrittenOutsideTheOrderTransaction() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "AZN", "XLON");
            String clOrdId = uniqueId("IT-RB");

            connection.setAutoCommit(false);
            try {
                client.placeOrder(clOrdId, ACCOUNT_ID, instrumentId,
                        "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("118.00"));
                connection.rollback();
            } finally {
                connection.setAutoCommit(true);
            }

            try (PreparedStatement statement = connection.prepareStatement(
                    "SELECT COUNT(*) FROM Risk.dbo.RiskCheckLog WHERE ClOrdId = ?")) {
                statement.setString(1, clOrdId);
                try (ResultSet rows = statement.executeQuery()) {
                    rows.next();
                    assertEquals(1, rows.getInt(1),
                            "the pre-trade check runs before the order transaction, so it must persist");
                }
            }

            try (PreparedStatement statement = connection.prepareStatement(
                    "SELECT COUNT(*) FROM dbo.[Order] WHERE ClOrdId = ?")) {
                statement.setString(1, clOrdId);
                try (ResultSet rows = statement.executeQuery()) {
                    rows.next();
                    assertEquals(0, rows.getInt(1), "the order itself was rolled back");
                }
            }
        }
    }

    private static void setRiskLimit(Connection connection, int accountId, int instrumentId,
            BigDecimal maxNetPositionQty) throws SQLException {
        try (CallableStatement call = connection.prepareCall(
                "{call Risk.dbo.usp_SetRiskLimit(?, ?, ?, ?, ?, ?)}")) {
            call.setInt(1, accountId);
            call.setInt(2, instrumentId);
            call.setNull(3, Types.DECIMAL);
            call.setNull(4, Types.DECIMAL);
            call.setBigDecimal(5, maxNetPositionQty);
            call.setString(6, "USD");
            call.execute();
        }
    }

    private static void deactivateRiskLimit(Connection connection, int accountId, int instrumentId)
            throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement("""
                UPDATE Risk.dbo.RiskLimit
                SET IsActive = 0
                WHERE AccountId = ? AND InstrumentId = ?
                """)) {
            statement.setInt(1, accountId);
            statement.setInt(2, instrumentId);
            statement.executeUpdate();
        }
    }
}
