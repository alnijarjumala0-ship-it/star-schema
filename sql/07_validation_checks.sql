-- ============================================================================
-- Script: 07_validation_checks.sql
-- Description: Comprehensive automated quality assurance and validation suite
--              for the Fisheries Star Schema.
--
-- Validates:
--   1. Schema and table existence (5 core tables)
--   2. Date dimension boundaries (2020-01-01 to 2030-12-31)
--   3. Date dimension exact row count (4,018 rows)
--   4. Fact table minimum row count (>= 200 rows)
--   5. Referential integrity (no orphaned foreign keys across all dimensions)
--   6. Measure constraints (positive weights, non-negative prices and totals)
--   7. Generated column mathematical precision (total_value = weight * price)
--   8. SCD Type 2 single current record constraint
--   9. SCD Type 2 non-overlapping temporal ranges
--  10. Point-in-time landing-to-vessel version temporal alignment
--
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

DROP TABLE IF EXISTS temp_validation_results;

CREATE TEMP TABLE temp_validation_results (
    test_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_category  VARCHAR(50) NOT NULL,
    test_name      VARCHAR(100) NOT NULL,
    status         VARCHAR(10) NOT NULL,
    observed_value TEXT NOT NULL,
    expected_value TEXT NOT NULL,
    details        TEXT NOT NULL
);

-- ----------------------------------------------------------------------------
-- Check 1: Schema Existence
-- ----------------------------------------------------------------------------
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Structure',
    'Schema dw exists',
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::TEXT,
    '1',
    'Verifies schema "dw" is registered in pg_namespace'
FROM pg_namespace 
WHERE nspname = 'dw';

-- ----------------------------------------------------------------------------
-- Check 2: All 5 Core Tables Exist in dw Schema
-- ----------------------------------------------------------------------------
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Structure',
    'All 5 warehouse tables exist',
    CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::TEXT || ' tables found: ' || STRING_AGG(table_name, ', ' ORDER BY table_name),
    '5 tables (dim_date, dim_port, dim_species, dim_vessel, fact_landing)',
    'Checks presence of all required star schema relations in schema dw'
FROM information_schema.tables 
WHERE table_schema = 'dw' 
  AND table_name IN ('dim_date', 'dim_port', 'dim_species', 'dim_vessel', 'fact_landing');

-- ----------------------------------------------------------------------------
-- Check 3: Date Dimension Boundary Span
-- ----------------------------------------------------------------------------
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Date Integrity',
    'Date dimension boundary dates (2020-01-01 to 2030-12-31)',
    CASE 
        WHEN MIN(full_date) = '2020-01-01'::DATE AND MAX(full_date) = '2030-12-31'::DATE 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END,
    'Min: ' || COALESCE(MIN(full_date)::TEXT, 'NULL') || ', Max: ' || COALESCE(MAX(full_date)::TEXT, 'NULL'),
    'Min: 2020-01-01, Max: 2030-12-31',
    'Ensures conformed calendar bounds span all 11 years required'
FROM dw.dim_date;

-- ----------------------------------------------------------------------------
-- Check 4: Date Dimension Exact Row Count (4,018 Dates)
-- ----------------------------------------------------------------------------
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Date Integrity',
    'Date dimension count is exactly 4,018 rows',
    CASE WHEN COUNT(*) = 4018 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::TEXT || ' dates',
    '4,018 dates (11 years including leap years 2020, 2024, 2028)',
    'Validates complete calendar coverage with zero missing or duplicate days'
FROM dw.dim_date;

-- ----------------------------------------------------------------------------
-- Check 5: Fact Table Minimum Row Count (>= 200 Rows)
-- ----------------------------------------------------------------------------
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Volume',
    'Fact table contains >= 200 rows',
    CASE WHEN COUNT(*) >= 200 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::TEXT || ' fact rows',
    '>= 200 rows',
    'Ensures analytical volume meets lab requirement threshold'
FROM dw.fact_landing;

-- ----------------------------------------------------------------------------
-- Check 6: Orphaned Foreign Keys in Fact Table
-- ----------------------------------------------------------------------------
WITH orphan_audit AS (
    SELECT 
        (SELECT COUNT(*) FROM dw.fact_landing f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_date d WHERE d.date_key = f.date_key)) AS date_orphans,
        (SELECT COUNT(*) FROM dw.fact_landing f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_port p WHERE p.port_key = f.port_key)) AS port_orphans,
        (SELECT COUNT(*) FROM dw.fact_landing f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_species s WHERE s.species_key = f.species_key)) AS species_orphans,
        (SELECT COUNT(*) FROM dw.fact_landing f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_vessel v WHERE v.vessel_key = f.vessel_key)) AS vessel_orphans
)
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Referential Integrity',
    'Zero orphaned foreign keys in fact_landing',
    CASE WHEN date_orphans = 0 AND port_orphans = 0 AND species_orphans = 0 AND vessel_orphans = 0 THEN 'PASS' ELSE 'FAIL' END,
    'date_orphans=' || date_orphans || ', port_orphans=' || port_orphans || ', species_orphans=' || species_orphans || ', vessel_orphans=' || vessel_orphans,
    'All foreign keys resolve to existing conformed dimension rows (0 orphans)',
    'Verifies foreign key enforcement between fact_landing and all four dimensions'
FROM orphan_audit;

-- ----------------------------------------------------------------------------
-- Check 7: Numeric Measure Constraints (Weights > 0, Price >= 0, Value >= 0)
-- ----------------------------------------------------------------------------
WITH measure_violations AS (
    SELECT 
        COUNT(CASE WHEN weight_kg <= 0 THEN 1 END) AS invalid_weights,
        COUNT(CASE WHEN price_per_kg < 0 THEN 1 END) AS invalid_prices,
        COUNT(CASE WHEN total_value < 0 THEN 1 END) AS invalid_values
    FROM dw.fact_landing
)
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Domain Constraints',
    'Catch measures satisfy positive/non-negative domain constraints',
    CASE WHEN invalid_weights = 0 AND invalid_prices = 0 AND invalid_values = 0 THEN 'PASS' ELSE 'FAIL' END,
    'invalid_weights=' || invalid_weights || ', invalid_prices=' || invalid_prices || ', invalid_values=' || invalid_values,
    '0 violations (weight_kg > 0, price_per_kg >= 0, total_value >= 0)',
    'Validates data quality constraints on commercial catch measures'
FROM measure_violations;

-- ----------------------------------------------------------------------------
-- Check 8: Stored Generated Column Calculation Precision
-- ----------------------------------------------------------------------------
WITH calculation_audit AS (
    SELECT COUNT(*) AS calculation_mismatches
    FROM dw.fact_landing
    WHERE total_value <> ROUND(weight_kg * price_per_kg, 2)
)
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Calculation Precision',
    'total_value equals ROUND(weight_kg * price_per_kg, 2) for all rows',
    CASE WHEN calculation_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
    calculation_mismatches::TEXT || ' calculation mismatches',
    '0 mismatches (exact stored generated column parity)',
    'Verifies generated column accurately computes financial totals without rounding errors'
FROM calculation_audit;

-- ----------------------------------------------------------------------------
-- Check 9: SCD Type 2 - Maximum of One Current Record Per Vessel
-- ----------------------------------------------------------------------------
WITH current_vessel_audit AS (
    SELECT vessel_id, COUNT(*) AS current_count
    FROM dw.dim_vessel
    WHERE is_current = TRUE
    GROUP BY vessel_id
    HAVING COUNT(*) > 1
)
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'SCD Type 2 Integrity',
    'Each vessel has at most one current dimension record',
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::TEXT || ' vessels with duplicate current records',
    '0 vessels with multiple is_current = TRUE versions',
    'Enforces business rule: a vessel can only occupy one active state at any given time'
FROM current_vessel_audit;

-- ----------------------------------------------------------------------------
-- Check 10: SCD Type 2 - Zero Overlapping Validity Periods
-- ----------------------------------------------------------------------------
WITH overlapping_audit AS (
    SELECT 
        v1.vessel_id,
        v1.vessel_key AS key1,
        v2.vessel_key AS key2
    FROM dw.dim_vessel v1
    JOIN dw.dim_vessel v2 
        ON v1.vessel_id = v2.vessel_id 
       AND v1.vessel_key < v2.vessel_key
       AND daterange(v1.effective_start_date, v1.effective_end_date, '[)') && 
           daterange(v2.effective_start_date, v2.effective_end_date, '[)')
)
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'SCD Type 2 Integrity',
    'No overlapping validity periods for the same vessel',
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::TEXT || ' overlapping version intervals found',
    '0 overlapping intervals [effective_start_date, effective_end_date)',
    'Guarantees non-overlapping temporal validity partitions per natural vessel key'
FROM overlapping_audit;

-- ----------------------------------------------------------------------------
-- Check 11: Point-in-Time Temporal Version Alignment for Fact Rows
-- ----------------------------------------------------------------------------
WITH fact_temporal_audit AS (
    SELECT COUNT(*) AS misaligned_facts
    FROM dw.fact_landing f
    JOIN dw.dim_date d ON f.date_key = d.date_key
    JOIN dw.dim_vessel v ON f.vessel_key = v.vessel_key
    WHERE NOT (d.full_date >= v.effective_start_date AND d.full_date < v.effective_end_date)
)
INSERT INTO temp_validation_results (test_category, test_name, status, observed_value, expected_value, details)
SELECT 
    'Temporal Alignment',
    'Fact landings link to valid vessel version for landing date',
    CASE WHEN misaligned_facts = 0 THEN 'PASS' ELSE 'FAIL' END,
    misaligned_facts::TEXT || ' misaligned fact rows',
    '0 misaligned rows (all landings satisfy start_date <= landing_date < end_date)',
    'Confirms fact rows accurately resolve to the temporal vessel version active on that date'
FROM fact_temporal_audit;

-- ----------------------------------------------------------------------------
-- Display Full QA Report
-- ----------------------------------------------------------------------------
SELECT 
    test_id,
    test_category,
    test_name,
    status,
    observed_value,
    expected_value,
    details
FROM temp_validation_results
ORDER BY test_id ASC;

-- ----------------------------------------------------------------------------
-- Strict Assertion Gate: Fail clearly if any check did not PASS
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_failed_count INTEGER;
    v_failure_list TEXT;
BEGIN
    SELECT COUNT(*), STRING_AGG(test_id::TEXT || ': ' || test_name || ' (Observed: ' || observed_value || ')', E'\n  - ')
    INTO v_failed_count, v_failure_list
    FROM temp_validation_results
    WHERE status = 'FAIL';

    IF v_failed_count > 0 THEN
        RAISE EXCEPTION E'\n=== QA VALIDATION SUITE FAILED ===\nTotal Failed Tests: %\nFailures:\n  - %\n==================================', 
            v_failed_count, v_failure_list;
    ELSE
        RAISE NOTICE E'\n=== ALL % QA TESTS PASSED SUCCESSFULLY! ===\nStar schema dimensional integrity, constraints, SCD Type 2 logic, and generated columns verified.\n',
            (SELECT COUNT(*) FROM temp_validation_results);
    END IF;
END $$;
