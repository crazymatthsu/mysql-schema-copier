package com.mssqlclone.localenv.jdbc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * The splitter is the one piece of this tool that silently corrupts a schema when it is
 * wrong: a mis-split batch either fails loudly or, worse, executes half a procedure body.
 * These cases all appear in the schema scripts.
 */
class SqlBatchSplitterTest {

    @Test
    @DisplayName("splits on a standalone GO and drops the separator")
    void splitsOnGo() {
        List<String> batches = SqlBatchSplitter.split("""
                SELECT 1;
                GO
                SELECT 2;
                GO
                """);

        assertEquals(List.of("SELECT 1;", "SELECT 2;"), batches);
    }

    @Test
    @DisplayName("keeps a trailing batch that has no GO")
    void keepsTrailingBatch() {
        List<String> batches = SqlBatchSplitter.split("SELECT 1;\nGO\nSELECT 2;");
        assertEquals(2, batches.size());
        assertEquals("SELECT 2;", batches.get(1));
    }

    @Test
    @DisplayName("ignores GO inside a string literal")
    void ignoresGoInsideString() {
        List<String> batches = SqlBatchSplitter.split("""
                INSERT INTO t (c) VALUES ('line one
                GO
                line two');
                """);

        assertEquals(1, batches.size());
        assertTrue(batches.getFirst().contains("line two"));
    }

    @Test
    @DisplayName("ignores GO inside a block comment, including nested comments")
    void ignoresGoInsideBlockComment() {
        List<String> batches = SqlBatchSplitter.split("""
                /* header
                GO
                   /* nested
                GO
                   */
                GO
                */
                SELECT 1;
                """);

        assertEquals(1, batches.size());
        assertTrue(batches.getFirst().endsWith("SELECT 1;"));
    }

    @Test
    @DisplayName("ignores GO inside a bracketed identifier")
    void ignoresGoInsideBracketedIdentifier() {
        List<String> batches = SqlBatchSplitter.split("""
                SELECT * FROM [weird
                GO
                name];
                """);

        assertEquals(1, batches.size());
    }

    @Test
    @DisplayName("does not split on identifiers that merely start with GO")
    void doesNotSplitOnGotoOrGoodbye() {
        List<String> batches = SqlBatchSplitter.split("""
                SELECT * FROM GOOD;
                GOTO done;
                SELECT 1;
                """);

        assertEquals(1, batches.size());
    }

    @Test
    @DisplayName("accepts a trailing line comment after the separator")
    void allowsCommentAfterSeparator() {
        List<String> batches = SqlBatchSplitter.split("SELECT 1;\nGO -- next\nSELECT 2;\n");
        assertEquals(List.of("SELECT 1;", "SELECT 2;"), batches);
    }

    @Test
    @DisplayName("expands GO n into n copies of the batch")
    void expandsRepeatCount() {
        List<String> batches = SqlBatchSplitter.split("INSERT INTO t VALUES (1);\nGO 3\n");
        assertEquals(3, batches.size());
        assertTrue(batches.stream().allMatch("INSERT INTO t VALUES (1);"::equals));
    }

    @Test
    @DisplayName("is case insensitive and tolerates surrounding whitespace")
    void isCaseInsensitive() {
        List<String> batches = SqlBatchSplitter.split("SELECT 1;\n   go   \nSELECT 2;\n");
        assertEquals(2, batches.size());
    }

    @Test
    @DisplayName("a line comment does not swallow the following line")
    void lineCommentEndsAtNewline() {
        List<String> batches = SqlBatchSplitter.split("""
                -- a comment mentioning 'an unclosed quote
                SELECT 1;
                GO
                SELECT 2;
                """);

        assertEquals(2, batches.size());
    }

    @Test
    @DisplayName("drops empty batches")
    void dropsEmptyBatches() {
        assertEquals(List.of(), SqlBatchSplitter.split("GO\n\nGO\n   \n"));
    }
}
