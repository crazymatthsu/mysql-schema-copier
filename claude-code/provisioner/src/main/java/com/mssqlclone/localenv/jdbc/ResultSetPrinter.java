package com.mssqlclone.localenv.jdbc;

import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/** Prints JDBC result sets as aligned text, for the ad-hoc {@code local-db sql} command. */
public final class ResultSetPrinter {

    private static final int MAX_COLUMN_WIDTH = 60;

    private ResultSetPrinter() {
    }

    /** Steps through every result set and update count a statement produced. */
    public static void printAll(Statement statement, boolean firstIsResultSet, Consumer<String> out)
            throws SQLException {
        boolean hasResultSet = firstIsResultSet;
        int setNumber = 0;
        while (true) {
            if (hasResultSet) {
                setNumber++;
                if (setNumber > 1) {
                    out.accept("");
                }
                try (ResultSet rows = statement.getResultSet()) {
                    print(rows, out);
                }
            } else {
                int updates = statement.getUpdateCount();
                if (updates == -1) {
                    break;
                }
                out.accept("(" + updates + " rows affected)");
            }
            hasResultSet = statement.getMoreResults();
        }
    }

    public static void print(ResultSet rows, Consumer<String> out) throws SQLException {
        ResultSetMetaData metaData = rows.getMetaData();
        int columnCount = metaData.getColumnCount();

        List<String> headers = new ArrayList<>(columnCount);
        for (int i = 1; i <= columnCount; i++) {
            headers.add(metaData.getColumnLabel(i));
        }

        List<List<String>> data = new ArrayList<>();
        while (rows.next()) {
            List<String> row = new ArrayList<>(columnCount);
            for (int i = 1; i <= columnCount; i++) {
                Object value = rows.getObject(i);
                row.add(value == null ? "NULL" : truncate(String.valueOf(value)));
            }
            data.add(row);
        }

        int[] widths = new int[columnCount];
        for (int i = 0; i < columnCount; i++) {
            widths[i] = headers.get(i).length();
        }
        for (List<String> row : data) {
            for (int i = 0; i < columnCount; i++) {
                widths[i] = Math.max(widths[i], row.get(i).length());
            }
        }

        out.accept(formatRow(headers, widths));
        StringBuilder rule = new StringBuilder();
        for (int i = 0; i < columnCount; i++) {
            if (i > 0) {
                rule.append("  ");
            }
            rule.append("-".repeat(widths[i]));
        }
        out.accept(rule.toString());

        for (List<String> row : data) {
            out.accept(formatRow(row, widths));
        }
        out.accept("(" + data.size() + " row" + (data.size() == 1 ? "" : "s") + ")");
    }

    private static String formatRow(List<String> values, int[] widths) {
        StringBuilder line = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) {
                line.append("  ");
            }
            line.append(String.format("%-" + widths[i] + "s", values.get(i)));
        }
        return line.toString().stripTrailing();
    }

    private static String truncate(String value) {
        String single = value.replace('\n', ' ').replace('\r', ' ');
        return single.length() <= MAX_COLUMN_WIDTH ? single : single.substring(0, MAX_COLUMN_WIDTH - 3) + "...";
    }
}
