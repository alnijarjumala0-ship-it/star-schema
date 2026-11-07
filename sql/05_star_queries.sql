-- ============================================================================
-- Script: 05_star_queries.sql
-- Description: Core analytical queries on the Fisheries Star Schema.
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

-- ============================================================================
-- QUERY 1: Kilograms Landed Per Month
-- ============================================================================
-- Business Purpose:
--   Monitors monthly fishery production trends, seasonality, and seasonal catch
--   volume fluctuations across all landing sites.
--
-- Dimensional Mechanics:
--   - Joins dw.fact_landing to dw.dim_date via date_key.
--   - Groups by calendar year_number, month_number, and month_name.
--   - Aggregates total catch using SUM(f.weight_kg).
--   - Sorts chronologically by year_number, month_number.
-- ============================================================================

SELECT 
    d.year_number,
    d.month_number,
    d.month_name,
    ROUND(SUM(f.weight_kg), 2)               AS total_landed_kg,
    ROUND(SUM(f.total_value), 2)             AS total_landing_value_php,
    COUNT(f.landing_id)                      AS total_landing_events
FROM dw.fact_landing f
JOIN dw.dim_date d 
    ON f.date_key = d.date_key
GROUP BY 
    d.year_number,
    d.month_number,
    d.month_name
ORDER BY 
    d.year_number ASC,
    d.month_number ASC;


-- ============================================================================
-- QUERY 2: Top Species Per Port
-- ============================================================================
-- Business Purpose:
--   Identifies the primary commercial catch profile of each landing facility,
--   enabling port authorities to optimize cold-storage and logistics for top species.
--
-- Dimensional Mechanics & Ranking Behavior:
--   - Joins dw.fact_landing to dw.dim_port (via port_key) and dw.dim_species (via species_key).
--   - First aggregates total landed kilograms per (port, species) in a CTE.
--   - Applies the window function DENSE_RANK() partitioned by port_name and ordered
--     by total landed kilograms descending.
--
-- Tie Handling & Ranking Explanation:
--   - DENSE_RANK() is chosen over RANK() and ROW_NUMBER():
--     * ROW_NUMBER() arbitrarily breaks ties based on engine row order, which would
--       unfairly exclude a tied species from the top 3.
--     * RANK() leaves gaps in rank numbers after ties (e.g. 1, 1, 3), potentially
--       omitting a 3rd-tier species if two tie for first.
--     * DENSE_RANK() ensures that if two species tie for Rank 1, both are reported as 1,
--       and the next distinct volume receives Rank 2 (1, 1, 2, 3), guaranteeing that
--       the top three distinct volume tiers are always represented.
--   - Filters species_rank <= 3 to return the top three tiers per port.
--   - Sorts by port_name ASC, species_rank ASC, total_landed_kg DESC.
-- ============================================================================

WITH species_port_aggregates AS (
    SELECT 
        p.port_name,
        s.species_name,
        s.species_category,
        ROUND(SUM(f.weight_kg), 2) AS total_landed_kg,
        ROUND(SUM(f.total_value), 2) AS total_value_php
    FROM dw.fact_landing f
    JOIN dw.dim_port p 
        ON f.port_key = p.port_key
    JOIN dw.dim_species s 
        ON f.species_key = s.species_key
    GROUP BY 
        p.port_name,
        s.species_name,
        s.species_category
),
ranked_species_per_port AS (
    SELECT 
        port_name,
        species_name,
        species_category,
        total_landed_kg,
        total_value_php,
        DENSE_RANK() OVER (
            PARTITION BY port_name 
            ORDER BY total_landed_kg DESC
        ) AS species_rank
    FROM species_port_aggregates
)
SELECT 
    port_name,
    species_name,
    species_category,
    total_landed_kg,
    total_value_php,
    species_rank
FROM ranked_species_per_port
WHERE species_rank <= 3
ORDER BY 
    port_name ASC,
    species_rank ASC,
    total_landed_kg DESC;


-- ============================================================================
-- QUERY 3: Total Landing Value Per Cooperative
-- ============================================================================
-- Business Purpose:
--   Evaluates economic production, commercial value, and volume share across
--   fisherfolk cooperatives for quota allocation and dividend distribution.
--
-- Dimensional Mechanics:
--   - Joins dw.fact_landing to dw.dim_vessel via vessel_key.
--   - Groups by v.cooperative_name.
--   - Aggregates total_value, weight_kg, and transaction count.
--   - Orders by total_landing_value_php DESC.
--
-- SCD Type 2 Impact on Cooperative Reporting:
--   - In our schema, fact_landing references vessel_key (surrogate key) rather than
--     the natural vessel_id.
--   - Each version of a vessel record represents that vessel's attributes during a specific
--     validity window [effective_start_date, effective_end_date).
--   - If Vessel 'VES-001' moves from Cooperative A to Cooperative B on 2024-07-01:
--     * Landings logged before 2024-07-01 point to vessel_key=1 (Cooperative A).
--     * Landings logged on/after 2024-07-01 point to vessel_key=9 (Cooperative B).
--   - Consequently, running this query over historical data attributes past revenue
--     accurately to Cooperative A, while new revenue is credited to Cooperative B.
--   - Had the fact table referenced vessel_id directly (or had an SCD Type 1 overwrite
--     been used), past landings would have been erroneously rewritten to Cooperative B,
--     corrupting financial statements and historical audits.
-- ============================================================================

SELECT 
    v.cooperative_name,
    ROUND(SUM(f.total_value), 2) AS total_landing_value_php,
    ROUND(SUM(f.weight_kg), 2)   AS total_landed_kg,
    COUNT(f.landing_id)          AS transaction_count,
    ROUND(AVG(f.price_per_kg), 2) AS avg_price_per_kg
FROM dw.fact_landing f
JOIN dw.dim_vessel v 
    ON f.vessel_key = v.vessel_key
GROUP BY 
    v.cooperative_name
ORDER BY 
    total_landing_value_php DESC;
