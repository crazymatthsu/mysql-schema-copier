package com.mssqlclone.tradingapp.model;

import java.math.BigDecimal;
import java.sql.Timestamp;

/** Value types returned by {@link com.mssqlclone.tradingapp.TradingClient}. */
public final class Records {

    private Records() {
    }

    public record Instrument(
            int instrumentId,
            String symbol,
            String mic,
            String instrumentName,
            String currencyCode,
            int lotSize,
            BigDecimal tickSize) {
    }

    public record PlacedOrder(
            long orderId,
            String clOrdId,
            String statusCode,
            String rejectReason) {

        public boolean accepted() {
            return "NEW".equals(statusCode);
        }
    }

    public record Fill(String execId, String newStatusCode, BigDecimal cumQty) {
    }

    public record BlotterRow(
            long orderId,
            String clOrdId,
            int accountId,
            String symbol,
            String sideCode,
            String statusCode,
            BigDecimal orderQty,
            BigDecimal cumQty,
            BigDecimal leavesQty,
            BigDecimal avgPx,
            String rejectReason,
            Timestamp createdAtUtc) {
    }

    public record PositionRow(
            int accountId,
            int instrumentId,
            String symbol,
            String currencyCode,
            BigDecimal quantity,
            BigDecimal avgPrice,
            BigDecimal lastPx,
            BigDecimal marketValue,
            BigDecimal unrealizedPnL,
            BigDecimal realizedPnL) {
    }

    public record ExposureRow(
            int accountId,
            String symbol,
            BigDecimal quantity,
            BigDecimal grossNotional,
            BigDecimal netNotional,
            BigDecimal maxNetPositionQty,
            BigDecimal limitUtilisationPct) {
    }
}
