# Fisheries Star Schema Data Warehouse (PostgreSQL 16+)

A complete, production-grade implementation of **Fisheries Star Schema Lab 1** in PostgreSQL 16+. This project demonstrates conformed dimensional modeling, deterministic synthetic data generation, advanced star schema analytical queries, and a fully verified **Slowly Changing Dimension Type 2 (SCD Type 2)** lifecycle with mathematical proof of historical report invariance.

---

## 1. Project Overview & Concepts

### 1.1 What is a Star Schema and Why Use It for Fisheries Data?
In operational databases (OLTP), catch landings are typically normalized across dozens of tables to optimize for fast inserts. While normalization prevents transactional anomalies, it makes analytical reporting (e.g., *"What is the monthly tuna volume by port over 3 years?"*) slow and complex, requiring dozens of table joins.

A **Star Schema** is a dimensional modeling pattern optimized for analytical querying (OLAP). It organizes data into:
- A central **Fact Table** containing numeric commercial measurements (kilograms landed, transaction values).
- Multiple conformed **Dimension Tables** radiating outward like the points of a star, providing context (Who? What? Where? When?).

In the fisheries sector, this schema enables rapid, multi-dimensional slicing and dicing:
- Tracking seasonal fish migration and biomass landing patterns.
- Comparing catch volume and market valuation across regional fish ports.
- Monitoring cooperative catches, vessel quotas, and species vulnerability.

### 1.2 Fact Table Grain
The grain defines the exact real-world event represented by a single row:
> **Fact Table Grain:** Exactly **one row per individual catch landing transaction or event** at a port facility, corresponding to an official commercial weigh-in ticket.

### 1.3 Role of Each Dimension Table
1. **`dw.dim_date` (Time Intelligence):** Conformed calendar dimension covering every calendar day from **2020-01-01 through 2030-12-31** (4,018 distinct dates). Enables temporal roll-ups by day, week, month, quarter, and year.
2. **`dw.dim_port` (Geographic Context):** Conformed geography dimension containing registered fishing ports, municipalities, provinces, and administrative regions.
3. **`dw.dim_species` (Marine Catch Taxonomy):** Conformed taxonomy dimension tracking commercial marine species (common name, scientific name, and ecological category: Pelagic, Demersal, Crustacean, Cephalopod).
4. **`dw.dim_vessel` (Vessel Dimension with SCD Type 2):** Conformed vessel dimension tracking fishing vessels, registration identifiers, vessel types, and cooperative memberships across time.

### 1.4 Business Keys vs. Surrogate Keys
- **Natural / Business Key (e.g. `vessel_id` = `'VES-001'`):** The operational identifier assigned to the entity in the real world. It remains constant over the vessel's lifetime.
- **Surrogate Key (e.g. `vessel_key` = `4` or `9`):** A database-generated integer primary key uniquely identifying a **single temporal version** of the dimension record.
- **Why Fact Tables MUST Reference the Surrogate Key:**
  If `dw.fact_landing` referenced `vessel_id`, changing a vessel's cooperative would retroactively rewrite past catch history under the new cooperative. By referencing `vessel_key`, every past landing remains permanently bound to the specific cooperative the vessel belonged to **on the exact date the landing took place**.

### 1.5 Slowly Changing Dimension Type 2 (SCD Type 2) & Date Boundaries
When a tracked vessel attribute (such as cooperative affiliation) changes:
1. The existing active record is closed by setting `is_current = FALSE` and updating its `effective_end_date` to the transfer date.
2. A new version record is inserted with a newly generated `vessel_key`, updated cooperative, `effective_start_date` set to the transfer date, `effective_end_date = '9999-12-31'`, and `is_current = TRUE`.
3. **Date Boundary Convention:** We implement the standard **half-open interval `[start, end)`** (inclusive start, exclusive end):
   $$\text{Record is valid when: } \text{effective\_start\_date} \le \text{landing\_date} < \text{effective\_end\_date}$$
   This ensures zero gaps and zero overlaps between consecutive versions.

---

## 2. Directory Structure

```text
fisheries-star-schema/
├── README.md                           # Comprehensive lab execution guide
├── sql/
│   ├── 01_create_schema_and_tables.sql # Schema DDL, constraints, generated columns & GiST indexes
│   ├── 02_populate_dim_date.sql        # Calendar date population (2020-2030, 4,018 days)
│   ├── 03_seed_dimensions.sql          # Seed ports, species, and initial vessel baseline
│   ├── 04_seed_fact_landing.sql        # Seed 300 deterministic landing transactions
│   ├── 05_star_queries.sql             # 3 core analytical star queries with commentary
│   ├── 06_scd_type2_demo.sql           # SCD Type 2 demonstration with proof of report invariance
│   └── 07_validation_checks.sql        # Automated QA validation suite with strict assertion gate
└── docs/
    └── schema_design.md                # Detailed technical schema specification & Mermaid ERD
```

---

## 3. Prerequisites & Environment Setup

### 3.1 Software Requirements
- **PostgreSQL 16 or later** (Tested on PostgreSQL 18.1).
- Any SQL GUI client: **pgAdmin 4**, **DBeaver**, or the standard command-line utility **`psql`**.

### 3.2 Database Connection
1. Launch **pgAdmin**, **DBeaver**, or your terminal.
2. Connect to your PostgreSQL server.
3. Create a clean database for the lab (e.g. `fisheries_dw`):
   ```sql
   CREATE DATABASE fisheries_dw;
   ```
4. Connect to `fisheries_dw` to execute the scripts.

---

## 4. Script Execution Order

Execute the SQL scripts in numerical order. Each script is self-contained and idempotent (safe to rerun).

| Step | Script | Execution Time | Purpose |
| :---: | :--- | :---: | :--- |
| **1** | `sql/01_create_schema_and_tables.sql` | ~1s | Creates schema `dw`, extensions (`btree_gist`), 5 core tables, check constraints, foreign keys, stored generated columns, and indexes. |
| **2** | `sql/02_populate_dim_date.sql` | ~1s | Populates 4,018 calendar dates from 2020-01-01 to 2030-12-31 using `generate_series()`. |
| **3** | `sql/03_seed_dimensions.sql` | ~1s | Seeds 7 fishing ports, 10 fish species, and 8 vessels (initial SCD2 baseline). |
| **4** | `sql/04_seed_fact_landing.sql` | ~1s | Generates 300 deterministic, reproducible landing transactions with automatic stored `total_value` calculation. |
| **5** | `sql/05_star_queries.sql` | ~1s | Runs the three analytical queries (monthly volume, top species per port, cooperative totals). |
| **6** | `sql/06_scd_type2_demo.sql` | ~1s | Executes a live SCD Type 2 transfer, adds post-change landings, and mathematically proves historical report invariance. |
| **7** | `sql/07_validation_checks.sql` | ~1s | Executes an automated 11-point QA test suite with strict assertion gates. |

### Running via `psql` (CLI)
From the project root directory, run:
```powershell
# Set your connection parameters
$env:PGHOST="localhost"
$env:PGPORT="5432"
$env:PGUSER="postgres"
$env:PGDATABASE="fisheries_dw"

# Run sequentially
psql -f sql/01_create_schema_and_tables.sql
psql -f sql/02_populate_dim_date.sql
psql -f sql/03_seed_dimensions.sql
psql -f sql/04_seed_fact_landing.sql
psql -f sql/05_star_queries.sql
psql -f sql/06_scd_type2_demo.sql
psql -f sql/07_validation_checks.sql
```

---

## 5. The Three Analytical Star Queries (`05_star_queries.sql`)

### Query 1: Kilograms Landed Per Month
- **Purpose:** Calculates total landed catch weight and gross commercial value by calendar month.
- **Dimensional Join:** Joins `dw.fact_landing` to conformed `dw.dim_date` on `date_key`.
- **Grouping:** `d.year_number, d.month_number, d.month_name`.
- **Aggregation:** `SUM(f.weight_kg)`, `SUM(f.total_value)`, `COUNT(f.landing_id)`.
- **Ordering:** Chronological (`ORDER BY d.year_number ASC, d.month_number ASC`).
- **Insight:** Reveals seasonal peaks (high summer yields) vs monsoon lulls, supporting quota and resource planning.

### Query 2: Top Species Per Port
- **Purpose:** Identifies the top 3 commercial species landed at each port facility.
- **Dimensional Join:** Joins `dw.fact_landing` with `dw.dim_port` and `dw.dim_species`.
- **Window Ranking:** Uses `DENSE_RANK() OVER (PARTITION BY port_name ORDER BY total_landed_kg DESC)`.
- **Tie Handling Explanation:**
  - `ROW_NUMBER()` arbitrarily separates tied species based on physical storage order.
  - `RANK()` leaves gaps in rank numbers after ties (e.g., 1, 1, 3), which would omit 3rd-tier species if two tie for first.
  - `DENSE_RANK()` assigns tied species the same rank without skipping subsequent rank numbers (1, 1, 2, 3), guaranteeing that the top 3 distinct volume tiers are always represented fairly.
- **Filter:** `WHERE species_rank <= 3`.

### Query 3: Total Landing Value Per Cooperative
- **Purpose:** Evaluates economic revenue, volume share, and transaction frequency across fisherfolk cooperatives.
- **Dimensional Join:** Joins `dw.fact_landing` to `dw.dim_vessel` on `vessel_key`.
- **Aggregation:** `SUM(f.total_value)`, `SUM(f.weight_kg)`, `COUNT(f.landing_id)`.
- **Ordering:** `ORDER BY total_landing_value_php DESC`.
- **SCD Type 2 Impact:** Because facts reference `vessel_key` (surrogate version key), landings logged before a vessel transferred cooperatives remain credited to the former cooperative. Past financial performance is never retroactively altered.

---

## 6. SCD Type 2 Demonstration & Verification (`06_scd_type2_demo.sql`)

### 6.1 Demonstration Scenario
1. **Initial Baseline:** Vessel `VES-001` (`F/V Ocean Sentinel`) is registered under `Navotas Deep Sea Fisherfolk Union` with `vessel_key = 4`.
2. **Transfer Event:** On **2024-07-01**, `VES-001` transfers to `Visayas Artisanal Fisherfolk Alliance`.
3. **Transition Execution:**
   - Active record (`vessel_key = 4`) is updated: `effective_end_date = '2024-07-01'`, `is_current = FALSE`.
   - New version (`vessel_key = 9`) is inserted: `effective_start_date = '2024-07-01'`, `effective_end_date = '9999-12-31'`, `is_current = TRUE`.
4. **New Landings Ingested:** Two new landings occur on `2024-08-15` and `2024-09-20`. During ingestion, point-in-time lookup matches `effective_start_date <= landing_date AND landing_date < effective_end_date`, resolving to `vessel_key = 9`.

### 6.2 Mathematical Proof of Historical Invariance
Before applying the change, the script records the historical cooperative figures (`full_date < '2024-07-01'`) into a temporary table `temp_baseline_cooperative_report`.

After the change and after inserting new landings, the exact historical report is re-executed and compared:

$$\Delta \text{Value} = \text{Post-Change Historical Value} - \text{Baseline Value} = 0.00 \text{ PHP}$$
$$\Delta \text{Weight} = \text{Post-Change Historical Weight} - \text{Baseline Weight} = 0.00 \text{ kg}$$

| Cooperative | Baseline Value (PHP) | Post-Change Value (PHP) | Variance | Audit Status |
| :--- | :---: | :---: | :---: | :---: |
| Gensan Tuna Fishermen Cooperative | 22,184,833.94 | 22,184,833.94 | **0.00** | **PASSED: 100% IDENTICAL** |
| Navotas Deep Sea Fisherfolk Union | 21,032,376.70 | 21,032,376.70 | **0.00** | **PASSED: 100% IDENTICAL** |
| Southern Tagalog Marine Cooperative | 23,981,515.64 | 23,981,515.64 | **0.00** | **PASSED: 100% IDENTICAL** |
| Visayas Artisanal Fisherfolk Alliance | 19,761,805.75 | 19,761,805.75 | **0.00** | **PASSED: 100% IDENTICAL** |

Simultaneously, a report for `full_date >= '2024-07-01'` confirms that the new landings for `VES-001` (4,050 kg, 877,000.00 PHP) correctly roll up under `Visayas Artisanal Fisherfolk Alliance`.

---

## 7. Quality Assurance & Validation Suite (`07_validation_checks.sql`)

The validation script runs an automated 11-point QA test suite and prints a formatted report:

```text
 test_id |     test_category     |                             test_name                              | status |                              observed_value                               |                                 expected_value                                 |                                         details                                          
---------+-----------------------+--------------------------------------------------------------------+--------+---------------------------------------------------------------------------+--------------------------------------------------------------------------------+------------------------------------------------------------------------------------------
       1 | Structure             | Schema dw exists                                                   | PASS   | 1                                                                         | 1                                                                              | Verifies schema "dw" is registered in pg_namespace
       2 | Structure             | All 5 warehouse tables exist                                       | PASS   | 5 tables found: dim_date, dim_port, dim_species, dim_vessel, fact_landing | 5 tables (dim_date, dim_port, dim_species, dim_vessel, fact_landing)           | Checks presence of all required star schema relations in schema dw
       3 | Date Integrity        | Date dimension boundary dates (2020-01-01 to 2030-12-31)           | PASS   | Min: 2020-01-01, Max: 2030-12-31                                          | Min: 2020-01-01, Max: 2030-12-31                                               | Ensures conformed calendar bounds span all 11 years required
       4 | Date Integrity        | Date dimension count is exactly 4,018 rows                         | PASS   | 4018 dates                                                                | 4,018 dates (11 years including leap years 2020, 2024, 2028)                   | Validates complete calendar coverage with zero missing or duplicate days
       5 | Volume                | Fact table contains >= 200 rows                                    | PASS   | 302 fact rows                                                             | >= 200 rows                                                                    | Ensures analytical volume meets lab requirement threshold
       6 | Referential Integrity | Zero orphaned foreign keys in fact_landing                         | PASS   | date_orphans=0, port_orphans=0, species_orphans=0, vessel_orphans=0       | All foreign keys resolve to existing conformed dimension rows (0 orphans)      | Verifies foreign key enforcement between fact_landing and all four dimensions
       7 | Domain Constraints    | Catch measures satisfy positive/non-negative domain constraints    | PASS   | invalid_weights=0, invalid_prices=0, invalid_values=0                     | 0 violations (weight_kg > 0, price_per_kg >= 0, total_value >= 0)              | Validates data quality constraints on commercial catch measures
       8 | Calculation Precision | total_value equals ROUND(weight_kg * price_per_kg, 2) for all rows | PASS   | 0 calculation mismatches                                                  | 0 mismatches (exact stored generated column parity)                            | Verifies generated column accurately computes financial totals without rounding errors
       9 | SCD Type 2 Integrity  | Each vessel has at most one current dimension record               | PASS   | 0 vessels with duplicate current records                                  | 0 vessels with multiple is_current = TRUE versions                             | Enforces business rule: a vessel can only occupy one active state at any given time
      10 | SCD Type 2 Integrity  | No overlapping validity periods for the same vessel                | PASS   | 0 overlapping version intervals found                                     | 0 overlapping intervals [effective_start_date, effective_end_date)             | Guarantees non-overlapping temporal validity partitions per natural vessel key
      11 | Temporal Alignment    | Fact landings link to valid vessel version for landing date        | PASS   | 0 misaligned fact rows                                                    | 0 misaligned rows (all landings satisfy start_date <= landing_date < end_date) | Confirms fact rows accurately resolve to the temporal vessel version active on that date
```

**Strict Assertion Gate:** If any check fails, the script executes `RAISE EXCEPTION`, aborting the execution with diagnostic error details.

---

## 8. Common Errors & Troubleshooting

1. **`ERROR: extension "btree_gist" is not available`**
   - *Cause:* Running on a stripped PostgreSQL package without standard contrib modules.
   - *Fix:* Ensure the `postgresql-contrib` package is installed on Linux (`sudo apt-get install postgresql-contrib`). On standard Windows/macOS installations, `btree_gist` is included by default.
2. **`ERROR: cannot insert into column "total_value"`**
   - *Cause:* `total_value` is defined as `GENERATED ALWAYS AS ... STORED`. It cannot be assigned manually in `INSERT` statements.
   - *Fix:* Omit `total_value` from your `INSERT` column list or specify `DEFAULT`.
3. **`ERROR: conflicting key value violates exclusion constraint "uq_dim_vessel_no_overlap"`**
   - *Cause:* An `INSERT` or `UPDATE` on `dw.dim_vessel` attempted to create a validity date range that overlaps with an existing record for the same `vessel_id`.
   - *Fix:* Verify that the old version's `effective_end_date` matches the new version's `effective_start_date` exactly.
4. **`ERROR: duplicate key value violates unique index "uq_dim_vessel_one_current"`**
   - *Cause:* Attempted to mark a second version of a vessel with `is_current = TRUE`.
   - *Fix:* Close the old version (`is_current = FALSE`) before or in the same transaction as inserting the new current record.
