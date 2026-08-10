USE Risk;
GO

MERGE dbo.RiskScenario AS target
USING (VALUES
    ('BASE_UP_5', 'Equity up five percent', 0.050000, 1),
    ('BASE_DOWN_10', 'Equity down ten percent', -0.100000, 1),
    ('LOCAL_STRESS_20', 'Local equity stress down twenty percent', -0.200000, 1)
) AS source (ScenarioCode, ScenarioName, EquityShockPct, IsActive)
ON target.ScenarioCode = source.ScenarioCode
WHEN MATCHED THEN UPDATE SET
    ScenarioName = source.ScenarioName,
    EquityShockPct = source.EquityShockPct,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT (ScenarioCode, ScenarioName, EquityShockPct, IsActive)
    VALUES (source.ScenarioCode, source.ScenarioName, source.EquityShockPct, source.IsActive);
GO

EXEC dbo.CalculateSimpleExposure @ScenarioCode = 'BASE_DOWN_10';
GO
