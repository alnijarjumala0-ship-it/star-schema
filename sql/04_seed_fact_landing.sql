-- ============================================================================
-- Script: 04_seed_fact_landing.sql
-- Description: Seeds 300 reproducible, deterministic landing transactions
--              into dw.fact_landing.
--
-- Notice: Data is synthetic and strictly illustrative for academic benchmarking.
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Deterministic Data Generation
-- We generate 300 rows using generate_series(1, 300).
-- All dates fall between January 2021 and May 2024, safely within dim_date (2020-2030)
-- and strictly preceding the SCD Type 2 demonstration boundary (2024-07-01).
-- ----------------------------------------------------------------------------
WITH generated_source AS (
    SELECT 
        i,
        -- Deterministic landing date: spread across 2021 to mid-2024
        ('2021-01-15'::DATE + (((i * 4 + (i % 7) * 3) % 1200) * INTERVAL '1 day'))::DATE AS landing_date,
        -- Deterministic foreign key selectors
        (((i * 3 + 2) % 7) + 1) AS port_selector,
        (((i * 7 + 1) % 10) + 1) AS species_selector,
        'VES-' || LPAD((((i * 5 + 3) % 8) + 1)::TEXT, 3, '0') AS target_vessel_id,
        -- Deterministic weight in kg (positive, realistic commercial catch: 120 kg - 2,700 kg)
        ROUND((120.0 + ((i * 43) % 2400) + ((i % 11) * 18.25))::NUMERIC, 2) AS weight_kg,
        -- Deterministic gear type and grade
        (ARRAY['Purse Seine', 'Trawl', 'Longline', 'Handline', 'Gillnet'])[(i % 5) + 1] AS gear_type,
        (ARRAY['Grade A', 'Grade A', 'Grade B', 'Grade B', 'Grade C'])[(i % 5) + 1] AS quality_grade
    FROM generate_series(1, 300) AS s(i)
),
resolved_transactions AS (
    SELECT
        src.i,
        d.date_key,
        p.port_key,
        s.species_key,
        v.vessel_key,
        src.weight_kg,
        -- Species-differentiated realistic pricing in PHP/kg
        CASE 
            WHEN s.species_key IN (1, 6, 9) THEN 
                ROUND((220.0 + ((src.i * 17) % 180) + ((src.i % 5) * 4.5))::NUMERIC, 2)
            WHEN s.species_key IN (2, 7, 8, 10) THEN 
                ROUND((140.0 + ((src.i * 13) % 120) + ((src.i % 4) * 3.5))::NUMERIC, 2)
            ELSE 
                ROUND((65.0 + ((src.i * 19) % 85) + ((src.i % 6) * 2.5))::NUMERIC, 2)
        END AS price_per_kg,
        'LND-' || TO_CHAR(d.full_date, 'YYYY') || '-' || LPAD(src.i::TEXT, 6, '0') AS landing_ticket_number,
        src.gear_type,
        src.quality_grade
    FROM generated_source src
    -- Conformed date join
    JOIN dw.dim_date d 
        ON d.full_date = src.landing_date
    -- Conformed port join by surrogate key
    JOIN dw.dim_port p 
        ON p.port_key = src.port_selector
    -- Conformed species join by surrogate key
    JOIN dw.dim_species s 
        ON s.species_key = src.species_selector
    -- Conformed SCD Type 2 vessel join by temporal validity window [start, end)
    JOIN dw.dim_vessel v 
        ON v.vessel_id = src.target_vessel_id
       AND v.effective_start_date <= src.landing_date 
       AND src.landing_date < v.effective_end_date
)
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
    date_key,
    port_key,
    species_key,
    vessel_key,
    weight_kg,
    price_per_kg,
    landing_ticket_number,
    gear_type,
    quality_grade
FROM resolved_transactions
ON CONFLICT (landing_ticket_number) DO NOTHING;

-- Verification output
SELECT 
    COUNT(*) AS total_fact_rows,
    MIN(d.full_date) AS earliest_landing_date,
    MAX(d.full_date) AS latest_landing_date,
    ROUND(SUM(weight_kg), 2) AS total_weight_kg,
    ROUND(SUM(total_value), 2) AS total_value_php,
    ROUND(AVG(price_per_kg), 2) AS overall_avg_price_per_kg
FROM dw.fact_landing f
JOIN dw.dim_date d ON f.date_key = d.date_key;
