/*
    Validation - seeded data is internally consistent.

    Positions in Trading are derived from executions in Orders through
    Trading.dbo.usp_ApplyExecution. If the clone lost a trigger, a constraint, or the
    cross-database EXEC permission, these two sides stop agreeing.
*/

SELECT
    CheckName = N'Seed volume: instruments, accounts, orders, executions',
    Detail    = CONCAT(N'instruments=', (SELECT COUNT(*) FROM ReferenceData.dbo.Instrument),
                       N' accounts=',    (SELECT COUNT(*) FROM Trading.dbo.Account),
                       N' orders=',      (SELECT COUNT(*) FROM Orders.dbo.[Order]),
                       N' executions=',  (SELECT COUNT(*) FROM Orders.dbo.Execution)),
    Passed    = CASE
        WHEN (SELECT COUNT(*) FROM ReferenceData.dbo.Instrument) >= 30
         AND (SELECT COUNT(*) FROM Trading.dbo.Account) >= 6
         AND (SELECT COUNT(*) FROM Orders.dbo.[Order]) >= 100
         AND (SELECT COUNT(*) FROM Orders.dbo.Execution) >= 50
        THEN 1 ELSE 0
    END;

SELECT
    CheckName = N'Order CumQty equals the sum of its executions',
    Detail    = CONCAT(N'mismatched orders=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM Orders.dbo.[Order] AS o
OUTER APPLY
(
    SELECT ExecQty = ISNULL(SUM(x.LastQty), 0)
    FROM Orders.dbo.Execution AS x
    WHERE x.OrderId = o.OrderId
) AS f
WHERE o.CumQty <> f.ExecQty;

SELECT
    CheckName = N'Filled orders have no remaining quantity',
    Detail    = CONCAT(N'violations=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM Orders.dbo.[Order] AS o
WHERE (o.StatusCode = 'FILLED' AND (o.LeavesQty <> 0 OR o.CumQty <> o.OrderQty))
   OR (o.StatusCode = 'PARTIALLY_FILLED' AND o.LeavesQty <= 0);

SELECT
    CheckName = N'Trading positions reconcile to Orders executions',
    Detail    = CONCAT(N'mismatched keys=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM
(
    SELECT
        o.AccountId,
        o.InstrumentId,
        NetQty = SUM(CASE WHEN o.SideCode = 'BUY' THEN x.LastQty ELSE -x.LastQty END)
    FROM Orders.dbo.Execution AS x
    INNER JOIN Orders.dbo.[Order] AS o
        ON o.OrderId = x.OrderId
    GROUP BY o.AccountId, o.InstrumentId
) AS fills
FULL OUTER JOIN Trading.dbo.Position AS p
    ON p.AccountId = fills.AccountId
   AND p.InstrumentId = fills.InstrumentId
WHERE ISNULL(p.Quantity, 0) <> ISNULL(fills.NetQty, 0);

SELECT
    CheckName = N'Every order references a live instrument and account',
    Detail    = CONCAT(N'orphans=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM Orders.dbo.[Order] AS o
WHERE NOT EXISTS (SELECT 1 FROM ReferenceData.dbo.Instrument AS i WHERE i.InstrumentId = o.InstrumentId)
   OR NOT EXISTS (SELECT 1 FROM Trading.dbo.Account AS a WHERE a.AccountId = o.AccountId);

SELECT
    CheckName = N'Pre-trade risk log holds both approvals and rejections',
    Detail    = CONCAT(N'approved=', SUM(CASE WHEN r.Decision = 'APPROVED' THEN 1 ELSE 0 END),
                       N' rejected=', SUM(CASE WHEN r.Decision = 'REJECTED' THEN 1 ELSE 0 END)),
    Passed    = CASE
        WHEN SUM(CASE WHEN r.Decision = 'APPROVED' THEN 1 ELSE 0 END) > 0
         AND SUM(CASE WHEN r.Decision = 'REJECTED' THEN 1 ELSE 0 END) > 0
        THEN 1 ELSE 0
    END
FROM Risk.dbo.RiskCheckLog AS r;

SELECT
    CheckName = N'Rejected orders carry a reason and no working quantity',
    Detail    = CONCAT(N'violations=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM Orders.dbo.[Order] AS o
WHERE o.StatusCode = 'REJECTED'
  AND (o.RejectReason IS NULL OR o.LeavesQty <> 0);

SELECT
    CheckName = N'Order audit trigger journalled every order',
    Detail    = CONCAT(N'orders=', (SELECT COUNT(*) FROM Orders.dbo.[Order]),
                       N' created-events=', (SELECT COUNT(*) FROM Orders.audit.OrderEvent WHERE EventType = 'CREATED')),
    Passed    = CASE
        WHEN (SELECT COUNT(*) FROM Orders.audit.OrderEvent WHERE EventType = 'CREATED')
           = (SELECT COUNT(*) FROM Orders.dbo.[Order])
        THEN 1 ELSE 0
    END;

SELECT
    CheckName = N'Position audit trigger journalled every position change',
    Detail    = CONCAT(N'history-rows=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) >= (SELECT COUNT(*) FROM Trading.dbo.Position) THEN 1 ELSE 0 END
FROM Trading.dbo.PositionHistory;

SELECT
    CheckName = N'Cash moved in the opposite direction to every fill',
    Detail    = CONCAT(N'accounts with cash rows=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM Trading.dbo.CashBalance;

SELECT
    CheckName = N'Every instrument has a current price snapshot',
    Detail    = CONCAT(N'missing=', COUNT(*)),
    Passed    = CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM ReferenceData.dbo.Instrument AS i
WHERE i.IsActive = 1
  AND NOT EXISTS (SELECT 1 FROM ReferenceData.mkt.PriceSnapshot AS p WHERE p.InstrumentId = i.InstrumentId);
