-- ============================================================================
-- Script: 02_populate_dim_date.sql
-- Description: Generates and populates all calendar dates from 2020-01-01
--              through 2030-12-31 inclusive (4,018 days) into dw.dim_date.
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

-- Populate dw.dim_date using generate_series()
INSERT INTO dw.dim_date (
    date_key,
    full_date,
    day_of_month,
    day_of_week,
    day_name,
    month_number,
    month_name,
    quarter_number,
    year_number,
    is_weekend
)
SELECT
    -- date_key: YYYYMMDD integer representation (e.g. 20240315)
    CAST(TO_CHAR(d, 'YYYYMMDD') AS INTEGER) AS date_key,
    
    -- full_date: Calendar DATE
    d::DATE AS full_date,
    
    -- day_of_month: 1 - 31
    CAST(EXTRACT(DAY FROM d) AS INTEGER) AS day_of_month,
    
    -- day_of_week: ISO 8601 day where 1 = Monday and 7 = Sunday
    CAST(EXTRACT(ISODOW FROM d) AS INTEGER) AS day_of_week,
    
    -- day_name: Full English weekday name ('Monday', 'Tuesday', etc.)
    -- TRIM removes trailing whitespace padded by standard TO_CHAR format
    TRIM(TO_CHAR(d, 'Day')) AS day_name,
    
    -- month_number: 1 - 12
    CAST(EXTRACT(MONTH FROM d) AS INTEGER) AS month_number,
    
    -- month_name: Full English month name ('January', 'February', etc.)
    TRIM(TO_CHAR(d, 'Month')) AS month_name,
    
    -- quarter_number: 1 - 4
    CAST(EXTRACT(QUARTER FROM d) AS INTEGER) AS quarter_number,
    
    -- year_number: Gregorian calendar year (e.g. 2024)
    CAST(EXTRACT(YEAR FROM d) AS INTEGER) AS year_number,
    
    -- is_weekend: TRUE for Saturday (ISO 6) and Sunday (ISO 7)
    CASE 
        WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN TRUE 
        ELSE FALSE 
    END AS is_weekend
FROM generate_series(
    '2020-01-01'::DATE, 
    '2030-12-31'::DATE, 
    '1 day'::INTERVAL
) AS s(d)
ON CONFLICT (date_key) DO UPDATE SET
    full_date      = EXCLUDED.full_date,
    day_of_month   = EXCLUDED.day_of_month,
    day_of_week    = EXCLUDED.day_of_week,
    day_name       = EXCLUDED.day_name,
    month_number   = EXCLUDED.month_number,
    month_name     = EXCLUDED.month_name,
    quarter_number = EXCLUDED.quarter_number,
    year_number    = EXCLUDED.year_number,
    is_weekend     = EXCLUDED.is_weekend;

-- Verification output
SELECT 
    COUNT(*) AS total_dates_loaded,
    MIN(full_date) AS earliest_date,
    MAX(full_date) AS latest_date,
    COUNT(CASE WHEN is_weekend = TRUE THEN 1 END) AS weekend_days,
    COUNT(CASE WHEN is_weekend = FALSE THEN 1 END) AS weekdays
FROM dw.dim_date;
