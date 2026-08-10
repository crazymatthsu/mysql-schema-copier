package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.mssqlclone.tradingapp.TradingClient;
import com.mssqlclone.tradingapp.model.Records.BlotterRow;
import com.mssqlclone.tradingapp.model.Records.Fill;
import com.mssqlclone.tradingapp.model.Records.PlacedOrder;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** The order state machine, driven entirely through the stored procedures. */
class OrderLifecycleIT extends IntegrationTestSupport {

    private static final int ACCOUNT_ID = 1003;   // FIRM_PRINCIPAL, generous limits

    @Test
    @DisplayName("place, partially fill, then complete an order")
    void fillsMoveTheOrderThroughItsStates() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "IBM", "XNYS");
            String clOrdId = uniqueId("IT-LIFE");

            PlacedOrder order = client.placeOrder(clOrdId, ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("300"), "LIMIT", new BigDecimal("225.00"));
            assertEquals("NEW", order.statusCode(), order.rejectReason());

            BlotterRow placed = client.findOrder(order.orderId()).orElseThrow();
            assertEquals(0, placed.cumQty().compareTo(BigDecimal.ZERO));
            assertEquals(0, placed.leavesQty().compareTo(new BigDecimal("300")));

            Fill partial = client.recordExecution(uniqueId("IT-EX"), order.orderId(),
                    new BigDecimal("100"), new BigDecimal("224.00"), new BigDecimal("1.00"));
            assertEquals("PARTIALLY_FILLED", partial.newStatusCode());
            assertEquals(0, partial.cumQty().compareTo(new BigDecimal("100")));

            Fill complete = client.recordExecution(uniqueId("IT-EX"), order.orderId(),
                    new BigDecimal("200"), new BigDecimal("225.00"), new BigDecimal("2.00"));
            assertEquals("FILLED", complete.newStatusCode());

            BlotterRow filled = client.findOrder(order.orderId()).orElseThrow();
            assertEquals(0, filled.leavesQty().compareTo(BigDecimal.ZERO));
            assertEquals(0, filled.cumQty().compareTo(new BigDecimal("300")));

            // (100 * 224.00 + 200 * 225.00) / 300 = 224.666667
            assertEquals(0, filled.avgPx().compareTo(new BigDecimal("224.666667")),
                    "weighted average price was " + filled.avgPx());
        }
    }

    @Test
    @DisplayName("a working order can be cancelled, and a terminal one cannot")
    void cancelOnlyWorksOnWorkingOrders() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "KO", "XNYS");

            PlacedOrder order = client.placeOrder(uniqueId("IT-CXL"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("60.00"));
            assertEquals("CANCELED", client.cancelOrder(order.orderId(), "IT_CANCEL"));

            BlotterRow cancelled = client.findOrder(order.orderId()).orElseThrow();
            assertEquals("CANCELED", cancelled.statusCode());
            assertEquals(0, cancelled.leavesQty().compareTo(BigDecimal.ZERO));

            SQLException failure = assertThrows(SQLException.class,
                    () -> client.cancelOrder(order.orderId(), "IT_CANCEL_AGAIN"));
            assertEquals(54022, failure.getErrorCode(), failure.getMessage());
        }
    }

    @Test
    @DisplayName("a duplicate client order id is rejected")
    void duplicateClientOrderIdIsRejected() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "PFE", "XNYS");
            String clOrdId = uniqueId("IT-DUP");

            client.placeOrder(clOrdId, ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("29.00"));

            SQLException failure = assertThrows(SQLException.class, () -> client.placeOrder(
                    clOrdId, ACCOUNT_ID, instrumentId, "BUY", new BigDecimal("100"),
                    "LIMIT", new BigDecimal("29.00")));
            assertEquals(54001, failure.getErrorCode(), failure.getMessage());
        }
    }

    @Test
    @DisplayName("a fill larger than the remaining quantity is refused")
    void overfillIsRefused() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "CSCO", "XNAS");

            PlacedOrder order = client.placeOrder(uniqueId("IT-OVER"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("57.00"));

            SQLException failure = assertThrows(SQLException.class,
                    () -> client.recordExecution(uniqueId("IT-EX"), order.orderId(),
                            new BigDecimal("101"), new BigDecimal("57.00"), BigDecimal.ZERO));
            assertEquals(54014, failure.getErrorCode(), failure.getMessage());

            // The failed fill must have left nothing behind.
            assertEquals(0, client.findOrder(order.orderId()).orElseThrow()
                    .cumQty().compareTo(BigDecimal.ZERO));
        }
    }

    @Test
    @DisplayName("a market order needs no limit price, a limit order does")
    void orderTypeRulesAreEnforced() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "WMT", "XNYS");

            PlacedOrder market = client.placeOrder(uniqueId("IT-MKT"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "MARKET", null);
            assertEquals("NEW", market.statusCode(), market.rejectReason());

            SQLException failure = assertThrows(SQLException.class, () -> client.placeOrder(
                    uniqueId("IT-LIM"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", null));
            assertEquals(54007, failure.getErrorCode(), failure.getMessage());
        }
    }

    @Test
    @DisplayName("the audit trigger journals creation and every fill")
    void auditTriggerJournalsTheLifecycle() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "DIS", "XNYS");

            PlacedOrder order = client.placeOrder(uniqueId("IT-AUD"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("200"), "LIMIT", new BigDecimal("97.00"));
            client.recordExecution(uniqueId("IT-EX"), order.orderId(),
                    new BigDecimal("200"), new BigDecimal("96.50"), BigDecimal.ZERO);

            try (PreparedStatement statement = connection.prepareStatement("""
                    SELECT EventType, NewStatusCode, NewCumQty
                    FROM audit.OrderEvent
                    WHERE OrderId = ?
                    ORDER BY EventId
                    """)) {
                statement.setLong(1, order.orderId());
                try (ResultSet rows = statement.executeQuery()) {
                    assertTrue(rows.next(), "no audit rows were written");
                    assertEquals("CREATED", rows.getString("EventType"));
                    assertEquals("NEW", rows.getString("NewStatusCode"));

                    assertTrue(rows.next(), "the fill was not journalled");
                    assertEquals("STATUS_CHANGE", rows.getString("EventType"));
                    assertEquals("FILLED", rows.getString("NewStatusCode"));
                    assertEquals(0, rows.getBigDecimal("NewCumQty").compareTo(new BigDecimal("200")));
                }
            }
        }
    }

    @Test
    @DisplayName("the blotter procedure filters by account and status")
    void blotterFiltersApply() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "XOM", "XNYS");

            client.placeOrder(uniqueId("IT-BLOT"), ACCOUNT_ID, instrumentId,
                    "SELL", new BigDecimal("100"), "LIMIT", new BigDecimal("120.00"));

            var working = client.blotter(ACCOUNT_ID, "NEW");
            assertTrue(working.stream().allMatch(row -> row.accountId() == ACCOUNT_ID));
            assertTrue(working.stream().allMatch(row -> "NEW".equals(row.statusCode())));
            assertTrue(working.size() > 0);
        }
    }
}
