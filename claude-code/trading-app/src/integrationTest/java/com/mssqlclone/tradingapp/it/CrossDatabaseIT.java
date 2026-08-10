package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.mssqlclone.tradingapp.TradingClient;
import com.mssqlclone.tradingapp.model.Records.ExposureRow;
import com.mssqlclone.tradingapp.model.Records.PlacedOrder;
import com.mssqlclone.tradingapp.model.Records.PositionRow;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * The dependencies that only exist between databases.
 *
 * <p>Keeping the local database names identical to the enterprise ones is what makes these
 * pass unchanged - rename Trading to LocalTrading and every one of them breaks.
 */
class CrossDatabaseIT extends IntegrationTestSupport {

    private static final int ACCOUNT_ID = 1003;

    @Test
    @DisplayName("a fill in Orders moves the position in Trading and the cash with it")
    void fillPropagatesAcrossDatabases() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "JPM", "XNYS");

            BigDecimal beforeQty = client.positionQuantity(ACCOUNT_ID, instrumentId);
            BigDecimal beforeCash = cashBalance(connection, ACCOUNT_ID, "USD");

            PlacedOrder order = client.placeOrder(uniqueId("IT-XDB"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("222.00"));
            assertEquals("NEW", order.statusCode(), order.rejectReason());

            client.recordExecution(uniqueId("IT-EX"), order.orderId(),
                    new BigDecimal("100"), new BigDecimal("220.00"), BigDecimal.ZERO);

            assertEquals(0, client.positionQuantity(ACCOUNT_ID, instrumentId)
                            .subtract(beforeQty).compareTo(new BigDecimal("100")),
                    "Trading.dbo.usp_ApplyExecution should have added 100 to the position");

            // Buying consumes cash: 100 * 220.00 = 22,000.
            assertEquals(0, beforeCash.subtract(cashBalance(connection, ACCOUNT_ID, "USD"))
                            .compareTo(new BigDecimal("22000.0000")),
                    "cash should have moved the opposite way to the fill");
        }
    }

    @Test
    @DisplayName("selling back realises P&L and leaves the position flat")
    void sellingBackRealisesProfitAndLoss() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            int instrumentId = instrumentId(connection, "CVX", "XNYS");

            BigDecimal startQty = client.positionQuantity(ACCOUNT_ID, instrumentId);
            BigDecimal startRealised = realisedPnL(connection, ACCOUNT_ID, instrumentId);

            PlacedOrder buy = client.placeOrder(uniqueId("IT-PNL"), ACCOUNT_ID, instrumentId,
                    "BUY", new BigDecimal("100"), "LIMIT", new BigDecimal("155.00"));
            client.recordExecution(uniqueId("IT-EX"), buy.orderId(),
                    new BigDecimal("100"), new BigDecimal("150.00"), BigDecimal.ZERO);

            PlacedOrder sell = client.placeOrder(uniqueId("IT-PNL"), ACCOUNT_ID, instrumentId,
                    "SELL", new BigDecimal("100"), "LIMIT", new BigDecimal("145.00"));
            client.recordExecution(uniqueId("IT-EX"), sell.orderId(),
                    new BigDecimal("100"), new BigDecimal("160.00"), BigDecimal.ZERO);

            assertEquals(0, client.positionQuantity(ACCOUNT_ID, instrumentId).compareTo(startQty),
                    "the round trip should leave the position where it started");

            BigDecimal realisedDelta = realisedPnL(connection, ACCOUNT_ID, instrumentId)
                    .subtract(startRealised);
            assertTrue(realisedDelta.compareTo(BigDecimal.ZERO) > 0,
                    "buying at 150 and selling at 160 should realise a profit, got " + realisedDelta);
        }
    }

    @Test
    @DisplayName("the valuation view prices Trading positions from ReferenceData")
    void positionValuationJoinsReferenceData() throws SQLException {
        try (Connection connection = connections.asLogin("trading_app", "Trading")) {
            TradingClient client = new TradingClient(connection);
            for (PositionRow position : client.positions(ACCOUNT_ID)) {
                assertNotNull(position.symbol(), "symbol comes from ReferenceData.dbo.Instrument");
                assertNotNull(position.lastPx(), "price comes from ReferenceData.mkt.vw_LatestPrice");
                assertNotNull(position.marketValue());
            }
        }
    }

    @Test
    @DisplayName("the three-part-name join from the design document runs unchanged")
    void documentedCrossDatabaseJoinRuns() throws SQLException {
        try (Connection connection = connections.asLogin("report_reader", "ReferenceData");
                Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery("""
                        SELECT COUNT(*) AS Matched
                        FROM ReferenceData.dbo.Instrument AS s
                        INNER JOIN Trading.dbo.Position AS p
                          ON s.InstrumentId = p.InstrumentId
                        """)) {
            rows.next();
            assertTrue(rows.getInt("Matched") > 0);
        }
    }

    @Test
    @DisplayName("EXEC Risk.dbo.usp_CalculateRisk reads Trading and ReferenceData")
    void riskProcedureSpansThreeDatabases() throws SQLException {
        try (Connection connection = connections.asLogin("risk_app", "Risk")) {
            TradingClient client = new TradingClient(connection);
            var exposures = client.calculateRisk(ACCOUNT_ID);
            assertTrue(exposures.size() > 0, "the account should hold positions by now");
            for (ExposureRow exposure : exposures) {
                assertNotNull(exposure.symbol());
                assertNotNull(exposure.grossNotional());
            }
        }
    }

    @Test
    @DisplayName("an unknown instrument is refused by the cross-database validation")
    void unknownInstrumentIsRefused() throws SQLException {
        try (Connection connection = connections.asLogin("orders_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            SQLException failure = org.junit.jupiter.api.Assertions.assertThrows(
                    SQLException.class,
                    () -> client.placeOrder(uniqueId("IT-BAD"), ACCOUNT_ID, -12345,
                            "BUY", new BigDecimal("100"), "MARKET", null));
            assertEquals(54005, failure.getErrorCode(), failure.getMessage());
        }
    }

    private static BigDecimal cashBalance(Connection connection, int accountId, String currency)
            throws SQLException {
        String sql = """
                SELECT Amount
                FROM Trading.dbo.CashBalance
                WHERE AccountId = ? AND CurrencyCode = ?
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setInt(1, accountId);
            statement.setString(2, currency);
            try (ResultSet rows = statement.executeQuery()) {
                return rows.next()
                        ? Optional.ofNullable(rows.getBigDecimal("Amount")).orElse(BigDecimal.ZERO)
                        : BigDecimal.ZERO;
            }
        }
    }

    private static BigDecimal realisedPnL(Connection connection, int accountId, int instrumentId)
            throws SQLException {
        String sql = """
                SELECT RealizedPnL
                FROM Trading.dbo.Position
                WHERE AccountId = ? AND InstrumentId = ?
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setInt(1, accountId);
            statement.setInt(2, instrumentId);
            try (ResultSet rows = statement.executeQuery()) {
                return rows.next() ? rows.getBigDecimal("RealizedPnL") : BigDecimal.ZERO;
            }
        }
    }
}
