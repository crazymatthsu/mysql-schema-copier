package com.mssqlclone.tradingapp;

import com.mssqlclone.localenv.config.LocalEnvConfig;
import com.mssqlclone.localenv.jdbc.ConnectionFactory;
import com.mssqlclone.tradingapp.model.Records.ExposureRow;
import com.mssqlclone.tradingapp.model.Records.Fill;
import com.mssqlclone.tradingapp.model.Records.Instrument;
import com.mssqlclone.tradingapp.model.Records.PlacedOrder;
import com.mssqlclone.tradingapp.model.Records.PositionRow;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.UUID;

/**
 * A scripted trading session against the local clone.
 *
 * <p>Run it with {@code ./gradlew :trading-app:run} once {@code ./local-env reset} has
 * finished. It connects as the {@code trading_app} login - not sa - so it exercises the
 * same login, user, role and permission chain the application uses upstream.
 */
public final class TradingAppDemo {

    private static final int ACCOUNT_ID = 1001;

    public static void main(String[] args) throws Exception {
        LocalEnvConfig config = LocalEnvConfig.loadDefault();
        ConnectionFactory connections = ConnectionFactory.forConfig(config);

        System.out.println("Connecting to " + connections.url("Orders") + " as trading_app");

        try (Connection connection = connections.asLogin("trading_app", "Orders")) {
            TradingClient client = new TradingClient(connection);
            String runId = UUID.randomUUID().toString().substring(0, 8).toUpperCase();

            Instrument instrument = client.findInstrument("MSFT", "XNAS")
                    .orElseThrow(() -> new IllegalStateException(
                            "MSFT is missing from ReferenceData - has the environment been seeded?"));
            BigDecimal lastPrice = client.lastPrice(instrument.instrumentId())
                    .orElseThrow(() -> new IllegalStateException("No price snapshot for MSFT"));

            heading("Reference data");
            System.out.printf("  %s (%s) id=%d ccy=%s lot=%d tick=%s last=%s%n",
                    instrument.symbol(), instrument.instrumentName(), instrument.instrumentId(),
                    instrument.currencyCode(), instrument.lotSize(), instrument.tickSize(), lastPrice);

            heading("Placing a limit order");
            BigDecimal limitPrice = lastPrice.multiply(new BigDecimal("1.002"))
                    .setScale(2, RoundingMode.HALF_UP);
            PlacedOrder order = client.placeOrder(
                    "DEMO-" + runId + "-1", ACCOUNT_ID, instrument.instrumentId(),
                    "BUY", new BigDecimal("400"), "LIMIT", limitPrice);
            System.out.printf("  orderId=%d status=%s reject=%s limit=%s%n",
                    order.orderId(), order.statusCode(), order.rejectReason(), limitPrice);

            heading("Filling it in two executions");
            Fill first = client.recordExecution("DEMOEX-" + runId + "-1", order.orderId(),
                    new BigDecimal("150"), lastPrice, new BigDecimal("1.50"));
            System.out.printf("  fill 1: status=%s cumQty=%s%n", first.newStatusCode(), first.cumQty());

            Fill second = client.recordExecution("DEMOEX-" + runId + "-2", order.orderId(),
                    new BigDecimal("250"), lastPrice.add(new BigDecimal("0.05")),
                    new BigDecimal("2.50"));
            System.out.printf("  fill 2: status=%s cumQty=%s%n", second.newStatusCode(), second.cumQty());

            heading("Position in Trading, valued from ReferenceData");
            for (PositionRow position : client.positions(ACCOUNT_ID)) {
                System.out.printf("  %-6s qty=%-10s avg=%-12s last=%-12s mv=%-14s unrealised=%s%n",
                        position.symbol(), position.quantity(), position.avgPrice(),
                        position.lastPx(), position.marketValue(), position.unrealizedPnL());
            }

            heading("Cancelling a working order");
            PlacedOrder working = client.placeOrder(
                    "DEMO-" + runId + "-2", ACCOUNT_ID, instrument.instrumentId(),
                    "BUY", new BigDecimal("100"), "LIMIT",
                    lastPrice.multiply(new BigDecimal("0.90")).setScale(2, RoundingMode.HALF_UP));
            System.out.printf("  placed %d (%s), cancel -> %s%n",
                    working.orderId(), working.statusCode(),
                    client.cancelOrder(working.orderId(), "DEMO_CANCEL"));

            heading("Pre-trade risk rejecting an oversized order");
            PlacedOrder rejected = client.placeOrder(
                    "DEMO-" + runId + "-3", ACCOUNT_ID, instrument.instrumentId(),
                    "BUY", new BigDecimal("999999"), "LIMIT", limitPrice);
            System.out.printf("  status=%s reason=%s%n", rejected.statusCode(), rejected.rejectReason());

            heading("EXEC Risk.dbo.usp_CalculateRisk " + ACCOUNT_ID);
            for (ExposureRow exposure : client.calculateRisk(ACCOUNT_ID)) {
                System.out.printf("  %-6s qty=%-10s gross=%-14s net=%-14s limit=%-10s used=%s%%%n",
                        exposure.symbol(), exposure.quantity(), exposure.grossNotional(),
                        exposure.netNotional(), exposure.maxNetPositionQty(),
                        exposure.limitUtilisationPct());
            }

            heading("Transaction rollback leaves no order behind");
            demonstrateRollback(connection, client, runId, instrument.instrumentId(), limitPrice);

            heading("Working orders on the blotter");
            client.blotter(ACCOUNT_ID, "NEW").stream()
                    .limit(5)
                    .forEach(row -> System.out.printf("  %-20s %-6s %-8s qty=%-8s leaves=%s%n",
                            row.clOrdId(), row.symbol(), row.statusCode(), row.orderQty(), row.leavesQty()));
        }
    }

    /**
     * The procedures commit their own work, so a caller-owned transaction is what makes a
     * multi-step operation atomic. Rolling back has to remove the order completely.
     */
    private static void demonstrateRollback(Connection connection, TradingClient client, String runId,
            int instrumentId, BigDecimal limitPrice) throws SQLException {
        connection.setAutoCommit(false);
        try {
            PlacedOrder doomed = client.placeOrder(
                    "DEMO-" + runId + "-4", ACCOUNT_ID, instrumentId,
                    "SELL", new BigDecimal("100"), "LIMIT", limitPrice);
            System.out.printf("  placed %d inside a transaction, rolling back%n", doomed.orderId());
            connection.rollback();
            System.out.printf("  order still present after rollback: %s%n",
                    client.findOrder(doomed.orderId()).isPresent());
        } finally {
            connection.setAutoCommit(true);
        }
    }

    private static void heading(String text) {
        System.out.println();
        System.out.println("== " + text);
    }
}
