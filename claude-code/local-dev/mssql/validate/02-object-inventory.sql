/*
    Validation - schema objects.

    A schema clone is only useful if the object inventory survived. These checks are the
    cheap version of a DACPAC drift report: enough to catch a half-applied refresh.
*/

;WITH Inventory AS
(
    SELECT DatabaseName = N'ReferenceData', ObjectType = o.type, ObjectCount = COUNT(*)
    FROM ReferenceData.sys.objects AS o
    WHERE o.is_ms_shipped = 0
    GROUP BY o.type
    UNION ALL
    SELECT N'Trading', o.type, COUNT(*)
    FROM Trading.sys.objects AS o
    WHERE o.is_ms_shipped = 0
    GROUP BY o.type
    UNION ALL
    SELECT N'Risk', o.type, COUNT(*)
    FROM Risk.sys.objects AS o
    WHERE o.is_ms_shipped = 0
    GROUP BY o.type
    UNION ALL
    SELECT N'Orders', o.type, COUNT(*)
    FROM Orders.sys.objects AS o
    WHERE o.is_ms_shipped = 0
    GROUP BY o.type
),
Expected AS
(
    SELECT *
    FROM
    (
        VALUES
            (N'ReferenceData', 'U',  6), (N'ReferenceData', 'V',  2), (N'ReferenceData', 'P',  3),
            (N'ReferenceData', 'TR', 1), (N'ReferenceData', 'SO', 1),
            (N'Trading',       'U',  6), (N'Trading',       'V',  2), (N'Trading',       'P',  3),
            (N'Trading',       'TR', 1),
            (N'Risk',          'U',  2), (N'Risk',          'V',  1), (N'Risk',          'P',  3),
            (N'Orders',        'U',  7), (N'Orders',        'V',  3), (N'Orders',        'P',  4),
            (N'Orders',        'TR', 1), (N'Orders',        'SO', 2)
    ) AS v (DatabaseName, ObjectType, MinimumCount)
)
SELECT
    CheckName = CONCAT(N'Object inventory ', e.DatabaseName, N'.', e.ObjectType),
    Detail    = CONCAT(N'found=', ISNULL(i.ObjectCount, 0), N' expected>=', e.MinimumCount),
    Passed    = CASE WHEN ISNULL(i.ObjectCount, 0) >= e.MinimumCount THEN 1 ELSE 0 END
FROM Expected AS e
LEFT JOIN Inventory AS i
    ON i.DatabaseName = e.DatabaseName
   AND i.ObjectType = e.ObjectType;

/* Named objects the applications bind to by name. */
;WITH RequiredObject AS
(
    SELECT *
    FROM
    (
        VALUES
            (N'ReferenceData.dbo.Instrument'),
            (N'ReferenceData.dbo.vw_ActiveInstrument'),
            (N'ReferenceData.mkt.vw_LatestPrice'),
            (N'ReferenceData.dbo.ufn_RoundToTick'),
            (N'ReferenceData.dbo.usp_GetInstrument'),
            (N'Trading.dbo.Position'),
            (N'Trading.dbo.vw_PositionValuation'),
            (N'Trading.dbo.usp_ApplyExecution'),
            (N'Risk.dbo.RiskLimit'),
            (N'Risk.dbo.usp_CheckOrderRisk'),
            (N'Risk.dbo.usp_CalculateRisk'),
            (N'Orders.dbo.Order'),
            (N'Orders.dbo.Execution'),
            (N'Orders.audit.OrderEvent'),
            (N'Orders.dbo.usp_PlaceOrder'),
            (N'Orders.dbo.usp_RecordExecution'),
            (N'Orders.dbo.usp_CancelOrder')
    ) AS v (QualifiedName)
)
SELECT
    CheckName = N'Object exists: ' + r.QualifiedName,
    Detail    = NULL,
    Passed    = CASE WHEN OBJECT_ID(QUOTENAME(PARSENAME(r.QualifiedName, 3)) + N'.'
                                 + QUOTENAME(PARSENAME(r.QualifiedName, 2)) + N'.'
                                 + QUOTENAME(PARSENAME(r.QualifiedName, 1))) IS NOT NULL
                     THEN 1 ELSE 0 END
FROM RequiredObject AS r;

/* Database roles are cloned objects; membership is environment-specific. */
;WITH RoleCheck AS
(
    SELECT DatabaseName = N'ReferenceData', RoleName = p.name
    FROM ReferenceData.sys.database_principals AS p
    WHERE p.type = 'R' AND p.is_fixed_role = 0 AND p.name <> N'public'
    UNION ALL
    SELECT N'Trading', p.name
    FROM Trading.sys.database_principals AS p
    WHERE p.type = 'R' AND p.is_fixed_role = 0 AND p.name <> N'public'
    UNION ALL
    SELECT N'Risk', p.name
    FROM Risk.sys.database_principals AS p
    WHERE p.type = 'R' AND p.is_fixed_role = 0 AND p.name <> N'public'
    UNION ALL
    SELECT N'Orders', p.name
    FROM Orders.sys.database_principals AS p
    WHERE p.type = 'R' AND p.is_fixed_role = 0 AND p.name <> N'public'
)
SELECT
    CheckName = N'Application roles present in ' + x.DatabaseName,
    Detail    = CAST(x.RoleCount AS NVARCHAR(10)) + N' custom roles',
    Passed    = CASE WHEN x.RoleCount >= 3 THEN 1 ELSE 0 END
FROM
(
    SELECT DatabaseName, RoleCount = COUNT(*)
    FROM RoleCheck
    GROUP BY DatabaseName
) AS x;
