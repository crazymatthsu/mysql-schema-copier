package com.mssqlclone.localenv.jdbc;

import java.util.ArrayList;
import java.util.List;

/**
 * Splits a T-SQL script on its {@code GO} batch separators.
 *
 * <p>{@code GO} is a client directive, not T-SQL: the JDBC driver rejects it, yet the
 * scripts need it because {@code CREATE VIEW}/{@code PROCEDURE}/{@code TRIGGER} must be
 * the first statement in their batch. Splitting therefore has to happen here, and it has
 * to respect the places a bare {@code GO} is just text - inside string literals, line and
 * block comments, and quoted or bracketed identifiers.
 */
public final class SqlBatchSplitter {

    private SqlBatchSplitter() {
    }

    private enum State {
        NORMAL,
        LINE_COMMENT,
        BLOCK_COMMENT,
        STRING,
        BRACKET_IDENTIFIER,
        QUOTED_IDENTIFIER
    }

    /**
     * @return the non-empty batches, in order, with {@code GO n} expanded to n copies
     */
    public static List<String> split(String script) {
        List<String> batches = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        State state = State.NORMAL;
        int blockCommentDepth = 0;

        for (String line : script.split("\r\n|\r|\n", -1)) {
            boolean startsClean = state == State.NORMAL;
            int separatorRepeat = startsClean ? batchSeparatorRepeat(line) : 0;

            if (separatorRepeat > 0) {
                addBatch(batches, current.toString(), separatorRepeat);
                current.setLength(0);
                continue;
            }

            current.append(line).append('\n');

            // Carry comment/literal state into the next line.
            ScanResult scanned = scanLine(line, state, blockCommentDepth);
            state = scanned.state();
            blockCommentDepth = scanned.blockCommentDepth();
        }

        addBatch(batches, current.toString(), 1);
        return batches;
    }

    private static void addBatch(List<String> batches, String batch, int repeat) {
        if (batch.isBlank()) {
            return;
        }
        String trimmed = batch.strip();
        for (int i = 0; i < repeat; i++) {
            batches.add(trimmed);
        }
    }

    /**
     * @return the repeat count when the line is a batch separator, otherwise 0
     */
    private static int batchSeparatorRepeat(String line) {
        String text = line.strip();
        if (text.isEmpty()) {
            return 0;
        }

        // A trailing line comment is allowed after the separator: "GO -- next batch".
        int commentAt = text.indexOf("--");
        if (commentAt >= 0) {
            text = text.substring(0, commentAt).strip();
        }
        if (text.length() < 2 || !text.regionMatches(true, 0, "GO", 0, 2)) {
            return 0;
        }

        String remainder = text.substring(2).strip();
        if (remainder.isEmpty()) {
            return 1;
        }
        try {
            int repeat = Integer.parseInt(remainder);
            return repeat > 0 ? repeat : 0;
        } catch (NumberFormatException e) {
            // "GOTO", "GO SELECT ..." and friends are not separators.
            return 0;
        }
    }

    private record ScanResult(State state, int blockCommentDepth) {
    }

    private static ScanResult scanLine(String line, State startState, int startDepth) {
        State state = startState;
        int depth = startDepth;

        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            char next = i + 1 < line.length() ? line.charAt(i + 1) : '\0';

            switch (state) {
                case NORMAL -> {
                    if (c == '-' && next == '-') {
                        state = State.LINE_COMMENT;
                        i++;
                    } else if (c == '/' && next == '*') {
                        state = State.BLOCK_COMMENT;
                        depth = 1;
                        i++;
                    } else if (c == '\'') {
                        state = State.STRING;
                    } else if (c == '[') {
                        state = State.BRACKET_IDENTIFIER;
                    } else if (c == '"') {
                        state = State.QUOTED_IDENTIFIER;
                    }
                }
                case BLOCK_COMMENT -> {
                    if (c == '/' && next == '*') {
                        depth++;
                        i++;
                    } else if (c == '*' && next == '/') {
                        depth--;
                        i++;
                        if (depth == 0) {
                            state = State.NORMAL;
                        }
                    }
                }
                case STRING -> {
                    if (c == '\'') {
                        if (next == '\'') {
                            i++; // escaped quote
                        } else {
                            state = State.NORMAL;
                        }
                    }
                }
                case BRACKET_IDENTIFIER -> {
                    if (c == ']') {
                        if (next == ']') {
                            i++;
                        } else {
                            state = State.NORMAL;
                        }
                    }
                }
                case QUOTED_IDENTIFIER -> {
                    if (c == '"') {
                        if (next == '"') {
                            i++;
                        } else {
                            state = State.NORMAL;
                        }
                    }
                }
                case LINE_COMMENT -> {
                    // Consumes the rest of the line.
                    return new ScanResult(State.NORMAL, depth);
                }
            }
        }

        // Line comments end with the line; everything else carries over.
        return new ScanResult(state == State.LINE_COMMENT ? State.NORMAL : state, depth);
    }
}
