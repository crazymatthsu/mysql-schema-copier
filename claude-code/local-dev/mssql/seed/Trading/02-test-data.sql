/*
    Trading - opening cash.

    Inserted only when absent: positions and cash are otherwise derived state, mutated
    exclusively by usp_ApplyExecution when the Orders seed replays its fills. Resetting
    the balances here on every run would contradict the executions already recorded.
*/

INSERT dbo.CashBalance (AccountId, CurrencyCode, Amount)
SELECT
    src.AccountId,
    src.CurrencyCode,
    src.Amount
FROM
(
    VALUES
        (1001, 'USD', 25000000.00),
        (1002, 'USD', 18000000.00),
        (1003, 'USD', 90000000.00),
        (1004, 'GBP', 12000000.00),
        (1005, 'USD', 40000000.00),
        (1006, 'JPY', 900000000.00)
) AS src (AccountId, CurrencyCode, Amount)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.CashBalance AS cb
    WHERE cb.AccountId = src.AccountId
      AND cb.CurrencyCode = src.CurrencyCode
);
GO
