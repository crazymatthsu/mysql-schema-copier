package com.mssqlclone.tradingapp.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * SELECT / INSERT / UPDATE / DELETE / MERGE against ReferenceData, plus the constraint
 * failures the application has to handle. Everything runs as {@code refdata_app}, the only
 * login with write access to reference data.
 */
class ReferenceDataCrudIT extends IntegrationTestSupport {

    @Test
    @DisplayName("insert, select, update and delete an instrument")
    void crudRoundTrip() throws SQLException {
        String symbol = uniqueSymbol();

        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData")) {
            int exchangeId = scalarInt(connection, "SELECT ExchangeId FROM dbo.Exchange WHERE Mic = 'XNAS'");

            try (PreparedStatement insert = connection.prepareStatement("""
                    INSERT INTO dbo.Instrument
                        (Symbol, InstrumentName, InstrumentType, ExchangeId, CurrencyCode, LotSize, TickSize)
                    OUTPUT inserted.InstrumentId
                    VALUES (?, ?, 'EQUITY', ?, 'USD', 1, 0.01)
                    """)) {
                insert.setString(1, symbol);
                insert.setString(2, "Integration Test Instrument");
                insert.setInt(3, exchangeId);
                try (ResultSet keys = insert.executeQuery()) {
                    keys.next();
                    int instrumentId = keys.getInt(1);
                    assertTrue(instrumentId >= 100000, "the sequence default should have supplied the id");

                    // SELECT through the view the applications actually use.
                    try (PreparedStatement select = connection.prepareStatement(
                            "SELECT InstrumentName, LotSize FROM dbo.vw_ActiveInstrument WHERE InstrumentId = ?")) {
                        select.setInt(1, instrumentId);
                        try (ResultSet rows = select.executeQuery()) {
                            assertTrue(rows.next());
                            assertEquals("Integration Test Instrument", rows.getString("InstrumentName"));
                        }
                    }

                    // UPDATE - the trigger must refresh UpdatedAtUtc.
                    try (PreparedStatement update = connection.prepareStatement(
                            "UPDATE dbo.Instrument SET LotSize = 100 WHERE InstrumentId = ?")) {
                        update.setInt(1, instrumentId);
                        assertEquals(1, update.executeUpdate());
                    }
                    try (PreparedStatement check = connection.prepareStatement(
                            "SELECT LotSize, CreatedAtUtc, UpdatedAtUtc FROM dbo.Instrument WHERE InstrumentId = ?")) {
                        check.setInt(1, instrumentId);
                        try (ResultSet rows = check.executeQuery()) {
                            rows.next();
                            assertEquals(100, rows.getInt("LotSize"));
                            assertTrue(rows.getTimestamp("UpdatedAtUtc")
                                            .compareTo(rows.getTimestamp("CreatedAtUtc")) >= 0,
                                    "trg_Instrument_SetUpdatedAt should have run");
                        }
                    }

                    try (PreparedStatement delete = connection.prepareStatement(
                            "DELETE FROM dbo.Instrument WHERE InstrumentId = ?")) {
                        delete.setInt(1, instrumentId);
                        assertEquals(1, delete.executeUpdate());
                    }
                }
            }
        }
    }

    @Test
    @DisplayName("usp_UpsertInstrument merges on the natural key")
    void mergeUpsert() throws SQLException {
        String symbol = uniqueSymbol();

        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData")) {
            int firstId = upsert(connection, symbol, "First name");
            int secondId = upsert(connection, symbol, "Renamed");
            assertEquals(firstId, secondId, "the second call must update, not insert");

            try (PreparedStatement select = connection.prepareStatement(
                    "SELECT InstrumentName FROM dbo.Instrument WHERE InstrumentId = ?")) {
                select.setInt(1, firstId);
                try (ResultSet rows = select.executeQuery()) {
                    rows.next();
                    assertEquals("Renamed", rows.getString(1));
                }
            }

            try (PreparedStatement delete = connection.prepareStatement(
                    "DELETE FROM dbo.Instrument WHERE InstrumentId = ?")) {
                delete.setInt(1, firstId);
                delete.executeUpdate();
            }
        }
    }

    @Test
    @DisplayName("a foreign key violation is raised, not silently ignored")
    void foreignKeyIsEnforced() throws SQLException {
        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData");
                Statement statement = connection.createStatement()) {
            SQLException failure = assertThrows(SQLException.class, () -> statement.executeUpdate("""
                    INSERT INTO dbo.Instrument
                        (Symbol, InstrumentName, InstrumentType, ExchangeId, CurrencyCode)
                    VALUES ('ITFK01', N'No such exchange', 'EQUITY', -999, 'USD')
                    """));
            assertEquals(547, failure.getErrorCode(), failure.getMessage());
            assertTrue(failure.getMessage().contains("FK_Instrument_Exchange"), failure.getMessage());
        }
    }

    @Test
    @DisplayName("check constraints survive the clone")
    void checkConstraintIsEnforced() throws SQLException {
        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData");
                Statement statement = connection.createStatement()) {
            SQLException failure = assertThrows(SQLException.class, () -> statement.executeUpdate("""
                    INSERT INTO dbo.Instrument
                        (Symbol, InstrumentName, InstrumentType, ExchangeId, CurrencyCode, TickSize)
                    SELECT 'ITCK01', N'Bad tick size', 'EQUITY', ExchangeId, 'USD', 0
                    FROM dbo.Exchange WHERE Mic = 'XNAS'
                    """));
            assertEquals(547, failure.getErrorCode(), failure.getMessage());
            assertTrue(failure.getMessage().contains("CK_Instrument_TickSize"), failure.getMessage());
        }
    }

    @Test
    @DisplayName("the filtered unique index on ISIN still rejects duplicates")
    void filteredUniqueIndexIsEnforced() throws SQLException {
        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData");
                Statement statement = connection.createStatement()) {
            SQLException failure = assertThrows(SQLException.class, () -> statement.executeUpdate("""
                    INSERT INTO dbo.Instrument
                        (Symbol, InstrumentName, InstrumentType, ExchangeId, CurrencyCode, Isin)
                    SELECT 'ITUQ01', N'Duplicate ISIN', 'EQUITY', ExchangeId, 'USD', 'US0378331005'
                    FROM dbo.Exchange WHERE Mic = 'XNAS'
                    """));
            assertTrue(failure.getErrorCode() == 2601 || failure.getErrorCode() == 2627,
                    "expected a unique index violation, got " + failure.getErrorCode()
                            + ": " + failure.getMessage());
        }
    }

    @Test
    @DisplayName("ufn_RoundToTick snaps prices to the instrument's tick grid")
    void scalarFunctionRoundsToTick() throws SQLException {
        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData");
                Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery("""
                        SELECT
                            Cent   = dbo.ufn_RoundToTick(232.507, 0.01),
                            Half   = dbo.ufn_RoundToTick(2851.30, 0.50),
                            NoTick = dbo.ufn_RoundToTick(10.123456, 0)
                        """)) {
            rows.next();
            assertEquals(0, rows.getBigDecimal("Cent").compareTo(new BigDecimal("232.51")));
            assertEquals(0, rows.getBigDecimal("Half").compareTo(new BigDecimal("2851.50")));
            assertEquals(0, rows.getBigDecimal("NoTick").compareTo(new BigDecimal("10.123456")));
        }
    }

    @Test
    @DisplayName("price snapshots upsert without duplicating the key")
    void priceSnapshotUpsert() throws SQLException {
        try (Connection connection = connections.asLogin("refdata_app", "ReferenceData")) {
            int instrumentId = instrumentId(connection, "IBM", "XNYS");
            String asOf = "2020-01-02T15:30:00";

            for (String price : new String[] {"111.11", "122.22"}) {
                try (CallableStatement call = connection.prepareCall(
                        "{call mkt.usp_UpsertPriceSnapshot(?, ?, ?, ?, ?, ?, ?)}")) {
                    call.setInt(1, instrumentId);
                    call.setString(2, asOf);
                    call.setBigDecimal(3, new BigDecimal(price));
                    call.setNull(4, Types.DECIMAL);
                    call.setNull(5, Types.DECIMAL);
                    call.setLong(6, 1000L);
                    call.setString(7, "TEST");
                    call.execute();
                }
            }

            try (PreparedStatement select = connection.prepareStatement("""
                    SELECT COUNT(*) AS Rows, MAX(LastPx) AS LastPx
                    FROM mkt.PriceSnapshot
                    WHERE InstrumentId = ? AND AsOfUtc = ?
                    """)) {
                select.setInt(1, instrumentId);
                select.setString(2, asOf);
                try (ResultSet rows = select.executeQuery()) {
                    rows.next();
                    assertEquals(1, rows.getInt("Rows"), "MERGE must not have inserted twice");
                    assertEquals(0, rows.getBigDecimal("LastPx").compareTo(new BigDecimal("122.22")));
                }
            }

            try (PreparedStatement delete = connection.prepareStatement(
                    "DELETE FROM mkt.PriceSnapshot WHERE InstrumentId = ? AND AsOfUtc = ?")) {
                delete.setInt(1, instrumentId);
                delete.setString(2, asOf);
                delete.executeUpdate();
            }
        }
    }

    private static int upsert(Connection connection, String symbol, String name) throws SQLException {
        try (CallableStatement call = connection.prepareCall(
                "{call dbo.usp_UpsertInstrument(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}")) {
            call.setString(1, symbol);
            call.setString(2, "XNAS");
            call.setString(3, name);
            call.setString(4, "EQUITY");
            call.setString(5, "USD");
            call.setNull(6, Types.CHAR);       // @Isin
            call.setNull(7, Types.CHAR);       // @Cusip
            call.setString(8, "TEST");         // @SectorCode
            call.setInt(9, 1);                 // @LotSize
            call.setBigDecimal(10, new BigDecimal("0.01"));
            call.setInt(11, 1);                // @IsActive
            call.registerOutParameter(12, Types.INTEGER);
            call.execute();
            Integer instrumentId = (Integer) call.getObject(12);
            assertNotNull(instrumentId, "the MERGE should have returned the affected id");
            return instrumentId;
        }
    }

    private static int scalarInt(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getInt(1);
        }
    }
}
