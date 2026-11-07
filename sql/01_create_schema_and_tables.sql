-- ============================================================================
-- Script: 01_create_schema_and_tables.sql
-- Description: Creates the 'dw' schema and all core dimensional model tables
--              for Fisheries Star Schema Lab 1.
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

-- 1. Create Data Warehouse Schema
CREATE SCHEMA IF NOT EXISTS dw;

-- 2. Enable btree_gist extension for SCD Type 2 exclusion constraints
--    This extension allows temporal range overlapping checks alongside scalar equality.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- Table: dw.dim_date
-- Role: Conformed Date Dimension
-- Grain: One row per calendar day from 2020-01-01 through 2030-12-31 (4,018 days)
-- Primary Key: date_key (Integer in YYYYMMDD format, e.g., 20240315)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_date (
    date_key        INTEGER PRIMARY KEY,             -- YYYYMMDD integer representation
    full_date       DATE NOT NULL UNIQUE,            -- Calendar date
    day_of_month    INTEGER NOT NULL,                -- 1 to 31
    day_of_week     INTEGER NOT NULL,                -- ISO 8601 day: 1 = Monday, 7 = Sunday
    day_name        VARCHAR(15) NOT NULL,            -- E.g., 'Monday', 'Tuesday'
    month_number    INTEGER NOT NULL,                -- 1 to 12
    month_name      VARCHAR(15) NOT NULL,            -- E.g., 'January', 'February'
    quarter_number  INTEGER NOT NULL,                -- 1 to 4
    year_number     INTEGER NOT NULL,                -- E.g., 2024
    is_weekend      BOOLEAN NOT NULL,                -- TRUE if Saturday or Sunday
    CONSTRAINT chk_dim_date_day_of_month CHECK (day_of_month BETWEEN 1 AND 31),
    CONSTRAINT chk_dim_date_day_of_week CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT chk_dim_date_month CHECK (month_number BETWEEN 1 AND 12),
    CONSTRAINT chk_dim_date_quarter CHECK (quarter_number BETWEEN 1 AND 4)
);

COMMENT ON TABLE dw.dim_date IS 'Conformed calendar date dimension covering 2020 through 2030.';
COMMENT ON COLUMN dw.dim_date.date_key IS 'Smart integer surrogate key formatted as YYYYMMDD.';
COMMENT ON COLUMN dw.dim_date.day_of_week IS 'ISO day of week where 1 = Monday and 7 = Sunday.';

-- ----------------------------------------------------------------------------
-- Table: dw.dim_port
-- Role: Geographic Dimension
-- Grain: One row per registered fishing port facility
-- Primary Key: port_key (Identity integer surrogate key)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_port (
    port_key        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    port_name       VARCHAR(100) NOT NULL,
    municipality    VARCHAR(100) NOT NULL,
    province        VARCHAR(100) NOT NULL,
    region          VARCHAR(100) NOT NULL,
    CONSTRAINT uq_dim_port_natural UNIQUE (port_name, municipality, province)
);

COMMENT ON TABLE dw.dim_port IS 'Geographic dimension storing landing ports and administrative regions.';
COMMENT ON COLUMN dw.dim_port.port_key IS 'Surrogate primary key generated automatically.';

-- ----------------------------------------------------------------------------
-- Table: dw.dim_species
-- Role: Catch Species Dimension
-- Grain: One row per commercially tracked fish/marine species
-- Primary Key: species_key (Identity integer surrogate key)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_species (
    species_key      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    species_name     VARCHAR(100) NOT NULL UNIQUE,
    scientific_name  VARCHAR(150) NOT NULL,
    species_category VARCHAR(50) NOT NULL,
    CONSTRAINT chk_dim_species_category CHECK (
        species_category IN ('Pelagic', 'Demersal', 'Crustacean', 'Cephalopod', 'Mollusk', 'Other')
    )
);

COMMENT ON TABLE dw.dim_species IS 'Biological classification of commercial marine catch.';
COMMENT ON COLUMN dw.dim_species.species_category IS 'Ecological category (e.g. Pelagic, Demersal, Crustacean, Cephalopod).';

-- ----------------------------------------------------------------------------
-- Table: dw.dim_vessel
-- Role: Vessel Dimension with Slowly Changing Dimension Type 2 (SCD Type 2)
-- Grain: One row per historical version of a fishing vessel
-- Business Key: vessel_id (Stable identifier across versions, e.g., 'VES-001')
-- Surrogate Key: vessel_key (Unique identity for every temporal version)
--
-- Temporal Convention:
-- - Effective Range: [effective_start_date, effective_end_date)
--   Start date is INCLUSIVE, end date is EXCLUSIVE.
-- - Active record: is_current = TRUE, effective_end_date = '9999-12-31'
-- - Historical record: is_current = FALSE, effective_end_date = date of next version
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_vessel (
    vessel_key           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vessel_id            VARCHAR(20) NOT NULL,            -- Stable business key
    vessel_name          VARCHAR(100) NOT NULL,
    cooperative_name     VARCHAR(100) NOT NULL,           -- Tracked descriptive attribute (changes over time)
    vessel_type          VARCHAR(50) NOT NULL,            -- E.g., 'Purse Seiner', 'Longliner'
    registration_number  VARCHAR(50) NOT NULL,            -- Official maritime authority registration
    effective_start_date DATE NOT NULL,                   -- Inclusive version start date
    effective_end_date   DATE NOT NULL DEFAULT '9999-12-31', -- Exclusive version end date (9999-12-31 for open-ended)
    is_current           BOOLEAN NOT NULL DEFAULT TRUE,   -- TRUE if currently active version
    CONSTRAINT chk_dim_vessel_dates CHECK (effective_start_date < effective_end_date)
);

-- Index 1: Enforce at the database level that exactly ONE record per vessel_id has is_current = TRUE
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_vessel_one_current 
    ON dw.dim_vessel (vessel_id) 
    WHERE is_current = TRUE;

-- Index 2: Prevent overlapping validity date ranges for the same vessel_id using GiST exclusion
ALTER TABLE dw.dim_vessel 
    DROP CONSTRAINT IF EXISTS uq_dim_vessel_no_overlap;

ALTER TABLE dw.dim_vessel
    ADD CONSTRAINT uq_dim_vessel_no_overlap
    EXCLUDE USING gist (
        vessel_id WITH =,
        daterange(effective_start_date, effective_end_date, '[)') WITH &&
    );

-- Index 3: Point-in-time lookup index for ETL fact mapping
CREATE INDEX IF NOT EXISTS idx_dim_vessel_lookup 
    ON dw.dim_vessel (vessel_id, effective_start_date, effective_end_date);

COMMENT ON TABLE dw.dim_vessel IS 'SCD Type 2 vessel dimension preserving historical vessel attributes.';
COMMENT ON COLUMN dw.dim_vessel.vessel_key IS 'Surrogate primary key identifying a specific version of a vessel.';
COMMENT ON COLUMN dw.dim_vessel.vessel_id IS 'Stable natural business identifier preserved across all historical versions.';
COMMENT ON COLUMN dw.dim_vessel.effective_start_date IS 'Inclusive start date of version validity [start, end).';
COMMENT ON COLUMN dw.dim_vessel.effective_end_date IS 'Exclusive end date of version validity [start, end).';

-- ----------------------------------------------------------------------------
-- Table: dw.fact_landing
-- Role: Central Fact Table
-- Grain: One row per individual landing event / transaction
--
-- Architectural Note on Surrogate Keys:
-- The fact table joins to dw.dim_vessel on vessel_key (surrogate key) rather
-- than vessel_id (business key). This ensures point-in-time accuracy: each
-- landing transaction is permanently tied to the exact cooperative, vessel name,
-- and registration that was active on the date of landing. If a vessel later
-- joins a different cooperative, historical landings remain correctly credited
-- to the former cooperative.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.fact_landing (
    landing_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key               INTEGER NOT NULL REFERENCES dw.dim_date(date_key),
    port_key               INTEGER NOT NULL REFERENCES dw.dim_port(port_key),
    species_key            INTEGER NOT NULL REFERENCES dw.dim_species(species_key),
    vessel_key             INTEGER NOT NULL REFERENCES dw.dim_vessel(vessel_key),
    weight_kg              NUMERIC(10,2) NOT NULL,
    price_per_kg           NUMERIC(10,2) NOT NULL,
    total_value            NUMERIC(12,2) GENERATED ALWAYS AS (ROUND(weight_kg * price_per_kg, 2)) STORED,
    landing_ticket_number  VARCHAR(30) NOT NULL UNIQUE,
    gear_type              VARCHAR(50) NOT NULL,
    quality_grade          VARCHAR(10) NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_fact_weight_positive CHECK (weight_kg > 0),
    CONSTRAINT chk_fact_price_nonnegative CHECK (price_per_kg >= 0),
    CONSTRAINT chk_fact_quality_grade CHECK (quality_grade IN ('Grade A', 'Grade B', 'Grade C'))
);

-- Foreign Key Indexes for High-Performance Dimensional Aggregations
CREATE INDEX IF NOT EXISTS idx_fact_landing_date ON dw.fact_landing (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_landing_port ON dw.fact_landing (port_key);
CREATE INDEX IF NOT EXISTS idx_fact_landing_species ON dw.fact_landing (species_key);
CREATE INDEX IF NOT EXISTS idx_fact_landing_vessel ON dw.fact_landing (vessel_key);
CREATE INDEX IF NOT EXISTS idx_fact_landing_port_species ON dw.fact_landing (port_key, species_key);

COMMENT ON TABLE dw.fact_landing IS 'Transactional fact table recording individual fishing vessel catch landing events.';
COMMENT ON COLUMN dw.fact_landing.total_value IS 'PostgreSQL 12+ generated stored column calculated as ROUND(weight_kg * price_per_kg, 2).';
