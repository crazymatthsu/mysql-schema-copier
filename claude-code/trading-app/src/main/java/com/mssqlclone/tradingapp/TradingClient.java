package com.mssqlclone.tradingapp;

import com.mssqlclone.tradingapp.model.Records.BlotterRow;
import com.mssqlclone.tradingapp.model.Records.ExposureRow;
import com.mssqlclone.tradingapp.model.Records.Fill;
import com.mssqlclone.tradingapp.model.Records.Instrument;
import com.mssqlclone.tradingapp.model.Records.PlacedOrder;
import com.mssqlclone.tradingapp.model.Records.PositionRow;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * The data access layer of the sample trading application.
 *
 * <p>Written the way the enterprise application is: three-part names for cross-database
 * reads, stored procedures for anything that mutates state, and no assumption that the
 * connected login can write directly to a table. Because the local databases carry the
 * same names, collation and permissions as the enterprise ones, this class needs no
 * local-only branches - only the connection string differs.
 */
public final class TradingClient {

    private final Connection connection;

    public TradingClient(Connection connection) {
        this.connection = connection;
    }

    public Connection connection() {
        return connection;
    }

    // ---------------------------------------------------------------- reference data

    /** Reads through the ReferenceData view; the connection may be to any database. */
    public Optional<Instrument> findInstrument(String symbol, String mic) throws SQLException {
        String sql = """
                SELECT TOP (1)
                    v.InstrumentId, v.Symbol, v.Mic, v.InstrumentName,
                    v.CurrencyCode, v.LotSize, v.TickSize
                FROM ReferenceData.dbo.vw_ActiveInstrument AS v
                WHERE v.Symbol = ?
                  AND (? IS NULL OR v.Mic = ?)
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, symbol);
            statement.setString(2, mic);
            statement.setString(3, mic);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) {
                    return Optional.empty();
                }
                return Optional.of(new Instrument(
                        rows.getInt("InstrumentId"),
                        rows.getString("Symbol"),
                        rows.getString("Mic"),
                        rows.getString("InstrumentName"),
                        rows.getString("CurrencyCode"),
                        rows.getInt("LotSize"),
                        rows.getBigDecimal("TickSize")));
            }
        }
    }

    public Optional<BigDecimal> lastPrice(int instrumentId) throws SQLException {
        String sql = """
                SELECT lp.LastPx
                FROM ReferenceData.mkt.vw_LatestPrice AS lp
                WHERE lp.InstrumentId = ?
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setInt(1, instrumentId);
            try (ResultSet rows = statement.executeQuery()) {
                return rows.next()
                        ? Optional.ofNullable(rows.getBigDecimal("LastPx"))
                        : Optional.empty();
            }
        }
    }

    // ---------------------------------------------------------------------- ordering

    /**
     * Places an order.
     *
     * <p>The procedure runs the pre-trade risk check in the Risk database and records the
     * order either way, so a rejection is a normal return value rather than an exception.
     */
    public PlacedOrder placeOrder(
            String clOrdId,
            int accountId,
            int instrumentId,
            String sideCode,
            BigDecimal orderQty,
            String orderTypeCode,
            BigDecimal limitPrice) throws SQLException {

        String sql = """
                {call Orders.dbo.usp_PlaceOrder(
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}
                """;
        try (CallableStatement call = connection.prepareCall(sql)) {
            call.setString(1, clOrdId);
            call.setInt(2, accountId);
            call.setInt(3, instrumentId);
            call.setString(4, sideCode);
            call.setBigDecimal(5, orderQty);
            call.setString(6, orderTypeCode);
            if (limitPrice == null) {
                call.setNull(7, Types.DECIMAL);
            } else {
                call.setBigDecimal(7, limitPrice);
            }
            call.setNull(8, Types.DECIMAL);      // @StopPrice
            call.setString(9, "DAY");            // @TifCode
            call.setNull(10, Types.INTEGER);     // @TraderId
            call.setString(11, "PRIMARY");       // @Venue
            call.setNull(12, Types.BIGINT);      // @ParentOrderId
            call.registerOutParameter(13, Types.BIGINT);   // @OrderId
            call.registerOutParameter(14, Types.VARCHAR);  // @StatusCode
            call.registerOutParameter(15, Types.VARCHAR);  // @RejectReason
            call.execute();

            return new PlacedOrder(
                    call.getLong(13),
                    clOrdId,
                    call.getString(14),
                    call.getString(15));
        }
    }

    /**
     * Records a fill.
     *
     * <p>One transaction inside the procedure covers the execution row, the order state,
     * and the position update in the Trading database.
     */
    public Fill recordExecution(String execId, long orderId, BigDecimal lastQty, BigDecimal lastPx,
            BigDecimal commission) throws SQLException {
        String sql = """
                {call Orders.dbo.usp_RecordExecution(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}
                """;
        try (CallableStatement call = connection.prepareCall(sql)) {
            call.setString(1, execId);
            call.setBigDecimal(2, lastQty);
            call.setBigDecimal(3, lastPx);
            call.setLong(4, orderId);
            call.setNull(5, Types.VARCHAR);      // @ClOrdId
            call.setNull(6, Types.VARCHAR);      // @VenueExecId
            call.setString(7, "R");              // @LiquidityFlag
            call.setBigDecimal(8, commission);
            call.setNull(9, Types.DATE);         // @TradeDate
            call.registerOutParameter(10, Types.VARCHAR);  // @NewStatusCode
            call.registerOutParameter(11, Types.DECIMAL);  // @NewCumQty
            call.execute();

            return new Fill(execId, call.getString(10), call.getBigDecimal(11));
        }
    }

    public String cancelOrder(long orderId, String reason) throws SQLException {
        try (CallableStatement call = connection.prepareCall(
                "{call Orders.dbo.usp_CancelOrder(?, ?, ?, ?)}")) {
            call.setLong(1, orderId);
            call.setNull(2, Types.VARCHAR);
            call.setString(3, reason);
            call.registerOutParameter(4, Types.VARCHAR);
            call.execute();
            return call.getString(4);
        }
    }

    public List<BlotterRow> blotter(Integer accountId, String statusCode) throws SQLException {
        List<BlotterRow> rows = new ArrayList<>();
        try (CallableStatement call = connection.prepareCall(
                "{call Orders.dbo.usp_GetOrderBlotter(?, ?, ?, ?)}")) {
            if (accountId == null) {
                call.setNull(1, Types.INTEGER);
            } else {
                call.setInt(1, accountId);
            }
            call.setNull(2, Types.DATE);
            if (statusCode == null) {
                call.setNull(3, Types.VARCHAR);
            } else {
                call.setString(3, statusCode);
            }
            call.setNull(4, Types.VARCHAR);

            try (ResultSet result = call.executeQuery()) {
                while (result.next()) {
                    rows.add(new BlotterRow(
                            result.getLong("OrderId"),
                            result.getString("ClOrdId"),
                            result.getInt("AccountId"),
                            result.getString("Symbol"),
                            result.getString("SideCode"),
                            result.getString("StatusCode"),
                            result.getBigDecimal("OrderQty"),
                            result.getBigDecimal("CumQty"),
                            result.getBigDecimal("LeavesQty"),
                            result.getBigDecimal("AvgPx"),
                            result.getString("RejectReason"),
                            result.getTimestamp("CreatedAtUtc")));
                }
            }
        }
        return rows;
    }

    public Optional<BlotterRow> findOrder(long orderId) throws SQLException {
        String sql = """
                SELECT
                    o.OrderId, o.ClOrdId, o.AccountId, i.Symbol, o.SideCode, o.StatusCode,
                    o.OrderQty, o.CumQty, o.LeavesQty, o.AvgPx, o.RejectReason, o.CreatedAtUtc
                FROM Orders.dbo.[Order] AS o
                INNER JOIN ReferenceData.dbo.Instrument AS i ON i.InstrumentId = o.InstrumentId
                WHERE o.OrderId = ?
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setLong(1, orderId);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) {
                    return Optional.empty();
                }
                return Optional.of(new BlotterRow(
                        rows.getLong("OrderId"),
                        rows.getString("ClOrdId"),
                        rows.getInt("AccountId"),
                        rows.getString("Symbol"),
                        rows.getString("SideCode"),
                        rows.getString("StatusCode"),
                        rows.getBigDecimal("OrderQty"),
                        rows.getBigDecimal("CumQty"),
                        rows.getBigDecimal("LeavesQty"),
                        rows.getBigDecimal("AvgPx"),
                        rows.getString("RejectReason"),
                        rows.getTimestamp("CreatedAtUtc")));
            }
        }
    }

    // --------------------------------------------------------------------- positions

    /** Reads the cross-database valuation view in Trading. */
    public List<PositionRow> positions(int accountId) throws SQLException {
        String sql = """
                SELECT
                    v.AccountId, v.InstrumentId, v.Symbol, v.CurrencyCode,
                    v.Quantity, v.AvgPrice, v.LastPx, v.MarketValue, v.UnrealizedPnL, v.RealizedPnL
                FROM Trading.dbo.vw_PositionValuation AS v
                WHERE v.AccountId = ?
                  AND v.Quantity <> 0
                ORDER BY v.Symbol
                """;
        List<PositionRow> rows = new ArrayList<>();
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setInt(1, accountId);
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    rows.add(new PositionRow(
                            result.getInt("AccountId"),
                            result.getInt("InstrumentId"),
                            result.getString("Symbol"),
                            result.getString("CurrencyCode"),
                            result.getBigDecimal("Quantity"),
                            result.getBigDecimal("AvgPrice"),
                            result.getBigDecimal("LastPx"),
                            result.getBigDecimal("MarketValue"),
                            result.getBigDecimal("UnrealizedPnL"),
                            result.getBigDecimal("RealizedPnL")));
                }
            }
        }
        return rows;
    }

    public BigDecimal positionQuantity(int accountId, int instrumentId) throws SQLException {
        String sql = "SELECT Trading.dbo.ufn_NetPositionQty(?, ?) AS Qty";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setInt(1, accountId);
            statement.setInt(2, instrumentId);
            try (ResultSet rows = statement.executeQuery()) {
                rows.next();
                return rows.getBigDecimal("Qty");
            }
        }
    }

    // -------------------------------------------------------------------------- risk

    /** {@code EXEC Risk.dbo.usp_CalculateRisk} - the first of its two result sets. */
    public List<ExposureRow> calculateRisk(int accountId) throws SQLException {
        List<ExposureRow> rows = new ArrayList<>();
        try (CallableStatement call = connection.prepareCall("{call Risk.dbo.usp_CalculateRisk(?)}")) {
            call.setInt(1, accountId);
            try (ResultSet result = call.executeQuery()) {
                while (result.next()) {
                    rows.add(new ExposureRow(
                            result.getInt("AccountId"),
                            result.getString("Symbol"),
                            result.getBigDecimal("Quantity"),
                            result.getBigDecimal("GrossNotional"),
                            result.getBigDecimal("NetNotional"),
                            result.getBigDecimal("MaxNetPositionQty"),
                            result.getBigDecimal("LimitUtilisationPct")));
                }
            }
        }
        return rows;
    }
}
