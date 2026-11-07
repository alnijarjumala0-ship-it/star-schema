-- ============================================================================
-- Script: 03_seed_dimensions.sql
-- Description: Seeds illustrative sample data for conformed dimensions:
--              dw.dim_port, dw.dim_species, and dw.dim_vessel (SCD Type 2).
--
-- Notice: Sample records are strictly illustrative for academic and lab
--         purposes and do not represent official fisheries statistics.
-- Target RDBMS: PostgreSQL 16+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Seed dw.dim_port
-- ----------------------------------------------------------------------------
INSERT INTO dw.dim_port (port_name, municipality, province, region)
VALUES
    ('General Santos Fish Port Complex', 'General Santos City', 'South Cotabato', 'Region XII - SOCCSKSARGEN'),
    ('Navotas Fish Port Complex',         'Navotas City',        'Metro Manila',   'National Capital Region'),
    ('Iloilo Fishing Port Complex',       'Iloilo City',         'Iloilo',         'Region VI - Western Visayas'),
    ('Lucena Fish Port Complex',          'Lucena City',         'Quezon',         'Region IV-A - CALABARZON'),
    ('Davao Fish Port Complex',           'Toril',               'Davao City',     'Region XI - Davao Region'),
    ('Zamboanga Fish Port Complex',       'Zamboanga City',      'Zamboanga del Sur', 'Region IX - Zamboanga Peninsula'),
    ('Sual Fish Port',                    'Sual',                'Pangasinan',     'Region I - Ilocos Region')
ON CONFLICT (port_name, municipality, province) DO UPDATE SET
    region = EXCLUDED.region;

-- ----------------------------------------------------------------------------
-- 2. Seed dw.dim_species
-- ----------------------------------------------------------------------------
INSERT INTO dw.dim_species (species_name, scientific_name, species_category)
VALUES
    ('Yellowfin Tuna',                      'Thunnus albacares',          'Pelagic'),
    ('Skipjack Tuna',                       'Katsuwonus pelamis',         'Pelagic'),
    ('Round Scad (Galunggong)',             'Decapterus macrosoma',       'Pelagic'),
    ('Bigeye Scad (Matangbaka)',            'Selar crumenophthalmus',     'Pelagic'),
    ('Indo-Pacific Mackerel (Hasahasa)',    'Rastrelliger brachysoma',    'Pelagic'),
    ('Leopard Coral Grouper (Lapu-lapu)',   'Plectropomus leopardus',     'Demersal'),
    ('Red Snapper (Maya-maya)',             'Lutjanus campechanus',       'Demersal'),
    ('Blue Swimming Crab (Alimasag)',       'Portunus pelagicus',         'Crustacean'),
    ('Giant Tiger Prawn (Sugpo)',           'Penaeus monodon',            'Crustacean'),
    ('Indian Squid (Pusit)',                'Uroteuthis duvaucelii',      'Cephalopod')
ON CONFLICT (species_name) DO UPDATE SET
    scientific_name  = EXCLUDED.scientific_name,
    species_category = EXCLUDED.species_category;

-- ----------------------------------------------------------------------------
-- 3. Seed dw.dim_vessel (Initial SCD Type 2 baseline)
--
-- Each vessel begins with effective_start_date = 2020-01-01,
-- effective_end_date = 9999-12-31, and is_current = TRUE.
-- Idempotency is preserved by inserting only if vessel_id is not already present.
-- ----------------------------------------------------------------------------
INSERT INTO dw.dim_vessel (
    vessel_id,
    vessel_name,
    cooperative_name,
    vessel_type,
    registration_number,
    effective_start_date,
    effective_end_date,
    is_current
)
SELECT 
    v.vessel_id,
    v.vessel_name,
    v.cooperative_name,
    v.vessel_type,
    v.registration_number,
    v.effective_start_date,
    v.effective_end_date,
    v.is_current
FROM (
    VALUES
        ('VES-001', 'F/V Ocean Sentinel', 'Navotas Deep Sea Fisherfolk Union', 'Purse Seiner',      'REG-PH-2018-001', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-002', 'F/V Pacific Harvest', 'Gensan Tuna Fishermen Cooperative', 'Purse Seiner',      'REG-PH-2019-042', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-003', 'F/V Blue Fin',        'Gensan Tuna Fishermen Cooperative', 'Longliner',         'REG-PH-2017-088', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-004', 'F/V Sea Rover',       'Visayas Artisanal Fisherfolk Alliance', 'Trawler',       'REG-PH-2020-105', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-005', 'F/V Aurora Star',     'Southern Tagalog Marine Cooperative', 'Handline Carrier', 'REG-PH-2021-019', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-006', 'F/V Island Seeker',   'Visayas Artisanal Fisherfolk Alliance', 'Multipurpose',   'REG-PH-2019-301', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-007', 'F/V Golden Horizon',  'Southern Tagalog Marine Cooperative', 'Trawler',         'REG-PH-2020-412', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE),
        ('VES-008', 'F/V Northern Light',  'Navotas Deep Sea Fisherfolk Union', 'Purse Seiner',      'REG-PH-2018-519', '2020-01-01'::DATE, '9999-12-31'::DATE, TRUE)
) AS v(vessel_id, vessel_name, cooperative_name, vessel_type, registration_number, effective_start_date, effective_end_date, is_current)
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_vessel exist WHERE exist.vessel_id = v.vessel_id
);

-- Verification summary
SELECT 'dw.dim_port' AS dimension_table, COUNT(*) AS row_count FROM dw.dim_port
UNION ALL
SELECT 'dw.dim_species' AS dimension_table, COUNT(*) AS row_count FROM dw.dim_species
UNION ALL
SELECT 'dw.dim_vessel' AS dimension_table, COUNT(*) AS row_count FROM dw.dim_vessel;
