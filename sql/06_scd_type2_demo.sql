-- ============================================================================
-- Script: 06_scd_type2_demo.sql
-- Description: Demonstrates Slowly Changing Dimension Type 2 (SCD Type 2)
--              lifecycle, point-in-time fact table resolution, and provides
--              mathematical proof of historical reporting invariance.
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 0: Idempotency Reset (Permits safe repeated executions of this demo)
-- If this demonstration was run previously, clean up demo fact rows and
-- restore VES-001 to its initial single-version baseline.
-- ----------------------------------------------------------------------------
DELETE FROM dw.fact_landing 
WHERE landing_ticket_number LIKE 'DEMO-SCD2-%';

DELETE FROM dw.dim_vessel 
WHERE vessel_id = 'VES-001' AND effective_start_date >= '2024-07-01';

UPDATE dw.dim_vessel
SET effective_end_date = '9999-12-31',
    is_current = TRUE
WHERE vessel_id = 'VES-001';

-- ----------------------------------------------------------------------------
-- STEP 1: Capture Baseline Historical Report (Pre-Change)
-- 
-- Date range: All historical dates preceding 2024-07-01.
-- Attribute examined: cooperative_name.
-- We record the exact aggregate figures into a temporary table.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS temp_baseline_cooperative_report;

CREATE TEMP TABLE temp_baseline_cooperative_report AS
SELECT 
    v.cooperative_name,
    ROUND(SUM(f.total_value), 2) AS baseline_value_php,
    ROUND(SUM(f.weight_kg), 2)   AS baseline_landed_kg,
    COUNT(f.landing_id)          AS baseline_trans_count
FROM dw.fact_landing f
JOIN dw.dim_vessel v 
    ON f.vessel_key = v.vessel_key
JOIN dw.dim_date d 
    ON f.date_key = d.date_key
WHERE d.full_date < '2024-07-01'
GROUP BY 
    v.cooperative_name
ORDER BY 
    v.cooperative_name;

-- Display baseline report
SELECT 
    'BASELINE BEFORE CHANGE (Dates < 2024-07-01)' AS report_stage,
    * 
FROM temp_baseline_cooperative_report;

-- ----------------------------------------------------------------------------
-- STEP 2: Execute SCD Type 2 Transition for Vessel 'VES-001'
--
-- Scenario:
--   On 2024-07-01, vessel 'VES-001' ('F/V Ocean Sentinel') transfers membership:
--   From: 'Navotas Deep Sea Fisherfolk Union'
--   To:   'Visayas Artisanal Fisherfolk Alliance'
--
-- Mechanics:
--   1. Close current record: set effective_end_date = '2024-07-01', is_current = FALSE.
--   2. Insert new record: new surrogate vessel_key, same vessel_id, updated cooperative,
--      effective_start_date = '2024-07-01', effective_end_date = '9999-12-31', is_current = TRUE.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_old_key INTEGER;
    v_new_key INTEGER;
BEGIN
    -- 1. Identify and close the active record
    SELECT vessel_key INTO v_old_key
    FROM dw.dim_vessel
    WHERE vessel_id = 'VES-001' AND is_current = TRUE;

    IF v_old_key IS NULL THEN
        RAISE EXCEPTION 'Active version of VES-001 not found.';
    END IF;

    UPDATE dw.dim_vessel
    SET effective_end_date = '2024-07-01',
        is_current = FALSE
    WHERE vessel_key = v_old_key;

    -- 2. Insert new version with new cooperative
    INSERT INTO dw.dim_vessel (
        vessel_id,
        vessel_name,
        cooperative_name,
        vessel_type,
        registration_number,
        effective_start_date,
        effective_end_date,
        is_current
    ) VALUES (
        'VES-001',
        'F/V Ocean Sentinel',
        'Visayas Artisanal Fisherfolk Alliance', -- New cooperative membership
        'Purse Seiner',
        'REG-PH-2018-001',
        '2024-07-01',
        '9999-12-31',
        TRUE
    )
    RETURNING vessel_key INTO v_new_key;

    RAISE NOTICE 'SCD Type 2 Transition Completed: Old vessel_key = %, New vessel_key = %', v_old_key, v_new_key;
END $$;

-- Inspect both versions of VES-001 in dw.dim_vessel
SELECT 
    vessel_key,
    vessel_id,
    vessel_name,
    cooperative_name,
    effective_start_date,
    effective_end_date,
    is_current
FROM dw.dim_vessel
WHERE vessel_id = 'VES-001'
ORDER BY vessel_key ASC;

-- ----------------------------------------------------------------------------
-- STEP 3: Insert Post-Change Fact Landings After 2024-07-01
--
-- Point-in-Time Key Resolution:
-- When logging landing events on 2024-08-15 and 2024-09-20, the ETL process
-- queries dw.dim_vessel where:
--    effective_start_date <= landing_date AND landing_date < effective_end_date
-- This correctly resolves to the NEW surrogate vessel_key!
-- ----------------------------------------------------------------------------
INSERT INTO dw.fact_landing (
    date_key,
    port_key,
    species_key,
    vessel_key,
    weight_kg,
    price_per_kg,
    landing_ticket_number,
    gear_type,
    quality_grade
)
SELECT 
    d.date_key,
    3 AS port_key,      -- Iloilo Fishing Port Complex
    1 AS species_key,   -- Yellowfin Tuna
    v.vessel_key,       -- Resolves to the newly inserted version of VES-001!
    1850.00 AS weight_kg,
    260.00 AS price_per_kg,
    'DEMO-SCD2-001' AS landing_ticket_number,
    'Purse Seine' AS gear_type,
    'Grade A' AS quality_grade
FROM dw.dim_date d
JOIN dw.dim_vessel v 
    ON v.vessel_id = 'VES-001'
   AND v.effective_start_date <= d.full_date 
   AND d.full_date < v.effective_end_date
WHERE d.full_date = '2024-08-15'::DATE

UNION ALL

SELECT 
    d.date_key,
    3 AS port_key,      -- Iloilo Fishing Port Complex
    2 AS species_key,   -- Skipjack Tuna
    v.vessel_key,       -- Resolves to the newly inserted version of VES-001!
    2200.00 AS weight_kg,
    180.00 AS price_per_kg,
    'DEMO-SCD2-002' AS landing_ticket_number,
    'Purse Seine' AS gear_type,
    'Grade A' AS quality_grade
FROM dw.dim_date d
JOIN dw.dim_vessel v 
    ON v.vessel_id = 'VES-001'
   AND v.effective_start_date <= d.full_date 
   AND d.full_date < v.effective_end_date
WHERE d.full_date = '2024-09-20'::DATE;

-- Verify the new landing records and their resolved surrogate key
SELECT 
    f.landing_ticket_number,
    d.full_date,
    v.vessel_id,
    v.vessel_name,
    v.vessel_key,
    v.cooperative_name,
    f.weight_kg,
    f.price_per_kg,
    f.total_value
FROM dw.fact_landing f
JOIN dw.dim_date d ON f.date_key = d.date_key
JOIN dw.dim_vessel v ON f.vessel_key = v.vessel_key
WHERE f.landing_ticket_number LIKE 'DEMO-SCD2-%'
ORDER BY d.full_date ASC;

-- ----------------------------------------------------------------------------
-- STEP 4: Proof 1 - Historical Reports Remain 100% Unchanged
--
-- We re-run the exact historical query for dates < 2024-07-01 and join it against
-- temp_baseline_cooperative_report.
--
-- Assertion: The variance in total value, landed kilograms, and transaction count
-- must be EXACTLY ZERO for every cooperative.
-- ----------------------------------------------------------------------------
SELECT 
    b.cooperative_name,
    b.baseline_value_php,
    ROUND(SUM(f.total_value), 2) AS post_change_historical_value_php,
    ROUND(ROUND(SUM(f.total_value), 2) - b.baseline_value_php, 2) AS variance_value_php,
    b.baseline_landed_kg,
    ROUND(SUM(f.weight_kg), 2) AS post_change_historical_kg,
    ROUND(ROUND(SUM(f.weight_kg), 2) - b.baseline_landed_kg, 2) AS variance_kg,
    b.baseline_trans_count,
    COUNT(f.landing_id) AS post_change_trans_count,
    CASE 
        WHEN ROUND(SUM(f.total_value), 2) = b.baseline_value_php 
         AND ROUND(SUM(f.weight_kg), 2) = b.baseline_landed_kg
         AND COUNT(f.landing_id) = b.baseline_trans_count
        THEN 'PASSED: 100% IDENTICAL'
        ELSE 'FAILED: HISTORICAL DATA ALTERED'
    END AS audit_status
FROM temp_baseline_cooperative_report b
JOIN dw.dim_vessel v 
    ON v.cooperative_name = b.cooperative_name
JOIN dw.fact_landing f 
    ON f.vessel_key = v.vessel_key
JOIN dw.dim_date d 
    ON f.date_key = d.date_key
WHERE d.full_date < '2024-07-01'
GROUP BY 
    b.cooperative_name,
    b.baseline_value_php,
    b.baseline_landed_kg,
    b.baseline_trans_count
ORDER BY 
    b.cooperative_name;

-- ----------------------------------------------------------------------------
-- STEP 5: Proof 2 - Post-Change Report Reflects New Cooperative
--
-- We run a report for landing dates on or after 2024-07-01.
-- This shows that the new landings for VES-001 now correctly roll up under
-- 'Visayas Artisanal Fisherfolk Alliance'.
-- ----------------------------------------------------------------------------
SELECT 
    v.cooperative_name,
    COUNT(f.landing_id)          AS post_change_trans_count,
    ROUND(SUM(f.weight_kg), 2)   AS post_change_landed_kg,
    ROUND(SUM(f.total_value), 2) AS post_change_total_value_php
FROM dw.fact_landing f
JOIN dw.dim_vessel v 
    ON f.vessel_key = v.vessel_key
JOIN dw.dim_date d 
    ON f.date_key = d.date_key
WHERE d.full_date >= '2024-07-01'
GROUP BY 
    v.cooperative_name
ORDER BY 
    post_change_total_value_php DESC;
