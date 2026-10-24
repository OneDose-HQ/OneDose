-- File: dbms/benchmarks.sql
-- Owner: Sivani  (only the owner edits this file)
-- Purpose: Measure speed: run EXPLAIN ANALYZE before indexes, create the indexes, run it again. Paste results into the pitch.
-- Inputs: Synthetic dataset.
-- Outputs: Before and after timings.
-- Depends on: 06_seed_synthetic.sql

\timing on

-- =====================================================================
-- SECTION 1: Verification of Dataset Scale and Fresh Optimizer Stats
-- =====================================================================
SELECT 'patients'           AS table_name, count(*) AS row_count FROM patients
UNION ALL
SELECT 'prescriptions'      AS table_name, count(*) AS row_count FROM prescriptions
UNION ALL
SELECT 'prescription_items' AS table_name, count(*) AS row_count FROM prescription_items
UNION ALL
SELECT 'patient_allergies'  AS table_name, count(*) AS row_count FROM patient_allergies
UNION ALL
SELECT 'patient_conditions' AS table_name, count(*) AS row_count FROM patient_conditions
UNION ALL
SELECT 'brands'             AS table_name, count(*) AS row_count FROM brands
UNION ALL
SELECT 'brand_ingredients'  AS table_name, count(*) AS row_count FROM brand_ingredients
UNION ALL
SELECT 'interactions'       AS table_name, count(*) AS row_count FROM interactions;

ANALYZE;

-- =====================================================================
-- SECTION 2: Clean Baseline (Drop Benchmark Indexes)
-- Drops only indexes created by this benchmark script to ensure clean BEFORE state.
-- Does not drop base schema constraint indexes or 01_schema.sql indexes.
-- =====================================================================
DROP INDEX IF EXISTS idx_bench_brands_trgm;
DROP INDEX IF EXISTS idx_bench_interactions_pair;
DROP INDEX IF EXISTS idx_bench_items_active_partial;
DROP INDEX IF EXISTS idx_bench_items_pat_dates;
DROP INDEX IF EXISTS idx_bench_brand_ingr_brand;
DROP INDEX IF EXISTS idx_bench_patient_allergies;

ANALYZE;

-- =====================================================================
-- SECTION 3: BEFORE Benchmarks (EXPLAIN ANALYZE, BUFFERS)
-- =====================================================================

-- Q1: Normalised fuzzy brand search
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM fn_search_brands('dolo650', 10);

-- Q2: Active medications and ingredients for a synthetic patient
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    patient_id,
    brand_id,
    brand_name,
    ingredient_id,
    ingredient_name,
    daily_ingredient_mg
FROM v_active_medications
WHERE patient_id = 1005;

-- Q3: Direct join evaluating interactions between patient active meds and candidate brand
EXPLAIN (ANALYZE, BUFFERS)
WITH pat_active AS (
    SELECT DISTINCT ingredient_id
    FROM v_active_medications
    WHERE patient_id = 1
),
cand_ingr AS (
    SELECT DISTINCT ingredient_id
    FROM brand_ingredients
    WHERE brand_id = 4
)
SELECT
    i.interaction_id,
    i.severity,
    i.mechanism,
    i.management
FROM pat_active pa
CROSS JOIN cand_ingr ci
JOIN interactions i ON (
    i.ingredient_a = LEAST(pa.ingredient_id, ci.ingredient_id)
    AND i.ingredient_b = GREATEST(pa.ingredient_id, ci.ingredient_id)
);

-- Q4: Historical medication lookup 6 months ago
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM fn_meds_as_of(1005, (current_date - interval '6 months')::date);

-- Q5: Top 20 most frequently prescribed brands
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    b.brand_id,
    b.brand_name,
    count(pi.item_id) AS total_prescriptions
FROM prescription_items pi
JOIN brands b ON b.brand_id = pi.brand_id
GROUP BY b.brand_id, b.brand_name
ORDER BY total_prescriptions DESC
LIMIT 20;

-- =====================================================================
-- SECTION 4: Create Benchmark Indexes
-- Distinct benchmark names avoid conflicting with existing 01_schema.sql indexes.
-- =====================================================================
-- 1. GIN trigram index on brand_name for fast fuzzy search
CREATE INDEX IF NOT EXISTS idx_bench_brands_trgm
    ON brands USING gin (brand_name gin_trgm_ops);

-- 2. Composite index on interaction pairs (ingredient_a, ingredient_b)
CREATE INDEX IF NOT EXISTS idx_bench_interactions_pair
    ON interactions (ingredient_a, ingredient_b);

-- 3. Partial index on ongoing prescription items (end_date IS NULL)
CREATE INDEX IF NOT EXISTS idx_bench_items_active_partial
    ON prescription_items (patient_id, brand_id)
    WHERE end_date IS NULL;

-- 4. Composite index covering patient historical date range lookups
CREATE INDEX IF NOT EXISTS idx_bench_items_pat_dates
    ON prescription_items (patient_id, start_date, end_date);

-- 5. Index on brand_ingredients brand_id
CREATE INDEX IF NOT EXISTS idx_bench_brand_ingr_brand
    ON brand_ingredients (brand_id);

-- 6. Index on patient_allergies patient_id
CREATE INDEX IF NOT EXISTS idx_bench_patient_allergies
    ON patient_allergies (patient_id);

ANALYZE;

-- =====================================================================
-- SECTION 5: AFTER Benchmarks (EXPLAIN ANALYZE, BUFFERS)
-- =====================================================================

-- Q1: Normalised fuzzy brand search
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM fn_search_brands('dolo650', 10);

-- Q2: Active medications and ingredients for a synthetic patient
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    patient_id,
    brand_id,
    brand_name,
    ingredient_id,
    ingredient_name,
    daily_ingredient_mg
FROM v_active_medications
WHERE patient_id = 1005;

-- Q3: Direct join evaluating interactions between patient active meds and candidate brand
EXPLAIN (ANALYZE, BUFFERS)
WITH pat_active AS (
    SELECT DISTINCT ingredient_id
    FROM v_active_medications
    WHERE patient_id = 1
),
cand_ingr AS (
    SELECT DISTINCT ingredient_id
    FROM brand_ingredients
    WHERE brand_id = 4
)
SELECT
    i.interaction_id,
    i.severity,
    i.mechanism,
    i.management
FROM pat_active pa
CROSS JOIN cand_ingr ci
JOIN interactions i ON (
    i.ingredient_a = LEAST(pa.ingredient_id, ci.ingredient_id)
    AND i.ingredient_b = GREATEST(pa.ingredient_id, ci.ingredient_id)
);

-- Q4: Historical medication lookup 6 months ago
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM fn_meds_as_of(1005, (current_date - interval '6 months')::date);

-- Q5: Top 20 most frequently prescribed brands
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    b.brand_id,
    b.brand_name,
    count(pi.item_id) AS total_prescriptions
FROM prescription_items pi
JOIN brands b ON b.brand_id = pi.brand_id
GROUP BY b.brand_id, b.brand_name
ORDER BY total_prescriptions DESC
LIMIT 20;

-- =====================================================================
-- SECTION 6: Benchmark Results Table
-- Note: Cells are left blank because benchmark execution requires an active
-- PostgreSQL instance with populated data. Values will be filled upon live execution.
-- =====================================================================
/*
| Query | Before (ms) | After (ms) | Plan change                                   |
|-------|-------------|------------|-----------------------------------------------|
| Q1    |             |            | Seq Scan -> Bitmap Index Scan on trgm         |
| Q2    |             |            | Seq Scan -> Index Scan on partial active      |
| Q3    |             |            | Hash Join -> Nested Loop / Index Scan         |
| Q4    |             |            | Seq Scan -> Bitmap Index Scan on (pat, dates) |
| Q5    |             |            | HashAggregate on items table                  |
*/
