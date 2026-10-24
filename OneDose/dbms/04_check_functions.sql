-- File: dbms/04_check_functions.sql
-- Owner: Bhavya  (only the owner edits this file)
-- Purpose: The safety checks: chk_duplicate, chk_interaction, chk_allergy, chk_contraindication, chk_dose,
--   fn_check_prescription (runs all five, ranked by severity) and fn_safe_alternatives (same indication, no conflicts).
--   Small helpers: fn_patient_active_ingredients, fn_in_class_tree, fn_check_core (checks 1-4, no dose needed).
--   Every function is read-only (STABLE): it only reports. Writing alerts is the job of 07_triggers.sql.
-- Inputs: Patient id, brand id, dose (units per intake), doses per day, optional date (default today).
-- Outputs: Ranked alert rows and a list of safer alternatives.
-- Depends on: 01_schema.sql, 03_lookup_functions.sql
--
-- Needs these two functions from 03 (agreed contract, names and columns must match):
--   fn_expand_brand(p_brand_id integer)     -> TABLE(ingredient_id integer, ingredient_name text, strength_mg numeric)
--   fn_class_descendants(p_class_id integer) -> TABLE(class_id integer)   (includes p_class_id itself)
--
-- Every check returns the same columns:
--   check_type, severity, ingredient_id, ingredient_name, related_ingredient_id, related_ingredient_name,
--   conflicting_item_id, mechanism, management, detail, source_id, source_name
--
-- Severity rules
--   duplicate        : major
--   interaction      : taken from the interactions / class_interactions row
--   allergy          : critical for the exact ingredient; for a drug-class allergy, major or the
--                      severity recorded on the patient's allergy, whichever is higher
--   contraindication : taken from the contraindications row
--   dose_limit       : critical at 1.5x the limit or more, otherwise major
--
-- If a function signature changes, DROP the old one first (CREATE OR REPLACE cannot change return columns).

-- ---------------------------------------------------------------------
-- Helper: what the patient takes on a date, one row per (item, ingredient)
-- daily_mg = dose_units * doses_per_day * strength_mg
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_patient_active_ingredients(p_patient_id bigint, p_on_date date DEFAULT current_date)
RETURNS TABLE(item_id bigint, brand_id integer, ingredient_id integer, daily_mg numeric)
LANGUAGE sql STABLE AS $$
    SELECT pi.item_id, pi.brand_id, bi.ingredient_id,
           pi.dose_units * pi.doses_per_day * bi.strength_mg
    FROM prescription_items pi
    JOIN brand_ingredients bi ON bi.brand_id = pi.brand_id
    WHERE pi.patient_id = p_patient_id
      AND pi.active_period @> p_on_date
$$;

-- ---------------------------------------------------------------------
-- Helper: is the ingredient in this drug class or any class below it?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_in_class_tree(p_ingredient_id integer, p_class_id integer)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM ingredient_classes ic
        WHERE ic.ingredient_id = p_ingredient_id
          AND ic.class_id IN (SELECT d.class_id FROM fn_class_descendants(p_class_id) d)
    )
$$;

-- ---------------------------------------------------------------------
-- Check 1: duplicate therapy
-- The new ingredient is already active under another brand (or the same one).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION chk_duplicate(p_patient_id bigint, p_brand_id integer, p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text)
LANGUAGE sql STABLE AS $$
    SELECT 'duplicate'::check_type,
           'major'::severity_level,
           i.ingredient_id, i.name,
           NULL::integer, NULL::text,
           min(a.item_id),
           'The same active ingredient is already prescribed.',
           'Check whether both medicines are really needed; the combined dose can be too high.',
           'Already active through: ' || string_agg(DISTINCT b.brand_name, ', '),
           NULL::integer, NULL::text
    FROM fn_expand_brand(p_brand_id) e
    JOIN fn_patient_active_ingredients(p_patient_id, p_on_date) a ON a.ingredient_id = e.ingredient_id
    JOIN ingredients i ON i.ingredient_id = e.ingredient_id
    JOIN brands b      ON b.brand_id = a.brand_id
    GROUP BY i.ingredient_id, i.name
$$;

-- ---------------------------------------------------------------------
-- Check 2: drug interaction
-- Self-join of new vs active ingredients, matched to the pair table
-- (stored once, lower id first) and to class-level pairs through the class tree.
-- If a pair matches both ways, only the most severe row is kept.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION chk_interaction(p_patient_id bigint, p_brand_id integer, p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text)
LANGUAGE sql STABLE AS $$
    WITH n AS (
        SELECT e.ingredient_id FROM fn_expand_brand(p_brand_id) e
    ),
    a AS (
        SELECT DISTINCT ON (x.ingredient_id) x.ingredient_id, x.item_id
        FROM fn_patient_active_ingredients(p_patient_id, p_on_date) x
        ORDER BY x.ingredient_id, x.item_id
    ),
    pairs AS (
        SELECT n.ingredient_id AS nid, a.ingredient_id AS aid, a.item_id
        FROM n JOIN a ON a.ingredient_id <> n.ingredient_id
    ),
    hits AS (
        SELECT p.nid, p.aid, p.item_id, it.severity, it.mechanism, it.management, it.source_id, 1 AS lvl
        FROM pairs p
        JOIN interactions it ON it.ingredient_a = LEAST(p.nid, p.aid)
                            AND it.ingredient_b = GREATEST(p.nid, p.aid)
        UNION ALL
        SELECT p.nid, p.aid, p.item_id, ci.severity, ci.mechanism, ci.management, ci.source_id, 2
        FROM pairs p
        JOIN class_interactions ci
          ON (fn_in_class_tree(p.nid, ci.class_a) AND fn_in_class_tree(p.aid, ci.class_b))
          OR (fn_in_class_tree(p.nid, ci.class_b) AND fn_in_class_tree(p.aid, ci.class_a))
    ),
    best AS (
        SELECT DISTINCT ON (h.nid, h.aid) h.*
        FROM hits h
        ORDER BY h.nid, h.aid, h.severity DESC, h.lvl
    )
    SELECT 'interaction'::check_type, b.severity,
           b.nid, ni.name, b.aid, ai.name,
           b.item_id, b.mechanism, b.management,
           'Interacts with ' || ai.name || ', which the patient already takes.',
           b.source_id, s.name
    FROM best b
    JOIN ingredients ni ON ni.ingredient_id = b.nid
    JOIN ingredients ai ON ai.ingredient_id = b.aid
    LEFT JOIN sources s ON s.source_id = b.source_id
$$;

-- ---------------------------------------------------------------------
-- Check 3: allergy
-- Allergy to the exact ingredient, or to a drug class (the class tree is walked,
-- so an allergy to "Penicillins" catches amoxicillin, and "Beta-lactams" catches both).
-- Only allergies valid on the date count.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION chk_allergy(p_patient_id bigint, p_brand_id integer, p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT
           'allergy'::check_type,
           CASE WHEN pa.ingredient_id IS NOT NULL THEN 'critical'::severity_level
                ELSE GREATEST('major'::severity_level, coalesce(pa.severity, 'major'::severity_level)) END,
           i.ingredient_id, i.name,
           NULL::integer, NULL::text,
           NULL::bigint,
           CASE WHEN pa.ingredient_id IS NOT NULL
                THEN 'The patient has a recorded allergy to ' || i.name || '.'
                ELSE 'The patient is allergic to the class ' || dc.name || ', and ' || i.name || ' belongs to it.'
           END,
           'Do not prescribe; choose a medicine from another class.',
           'Recorded reaction: ' || coalesce(pa.reaction, 'not recorded'),
           NULL::integer, NULL::text
    FROM fn_expand_brand(p_brand_id) e
    JOIN ingredients i ON i.ingredient_id = e.ingredient_id
    JOIN patient_allergies pa
      ON pa.patient_id = p_patient_id
     AND pa.valid_from <= p_on_date
     AND (pa.valid_to IS NULL OR pa.valid_to > p_on_date)
     AND ( pa.ingredient_id = e.ingredient_id
        OR (pa.class_id IS NOT NULL AND fn_in_class_tree(e.ingredient_id, pa.class_id)) )
    LEFT JOIN drug_classes dc ON dc.class_id = pa.class_id
$$;

-- ---------------------------------------------------------------------
-- Check 4: drug-disease contraindication
-- Ingredient listed as contraindicated for a diagnosis the patient has on the date.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION chk_contraindication(p_patient_id bigint, p_brand_id integer, p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT
           'contraindication'::check_type,
           c.severity,
           i.ingredient_id, i.name,
           NULL::integer, NULL::text,
           NULL::bigint,
           coalesce(c.note, i.name || ' is contraindicated in ' || cd.name || '.'),
           'Avoid in this patient or choose a different medicine.',
           'Patient condition: ' || cd.name,
           c.source_id, s.name
    FROM fn_expand_brand(p_brand_id) e
    JOIN ingredients i        ON i.ingredient_id = e.ingredient_id
    JOIN contraindications c  ON c.ingredient_id = e.ingredient_id
    JOIN patient_conditions pc
      ON pc.patient_id = p_patient_id
     AND pc.condition_id = c.condition_id
     AND pc.valid_from <= p_on_date
     AND (pc.valid_to IS NULL OR pc.valid_to > p_on_date)
    JOIN conditions cd        ON cd.condition_id = c.condition_id
    LEFT JOIN sources s       ON s.source_id = c.source_id
$$;

-- ---------------------------------------------------------------------
-- Check 5: maximum daily dose
-- A window SUM adds the daily mg of every active brand containing the ingredient
-- to the new prescription, then compares with the limit for the patient's age band.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION chk_dose(p_patient_id bigint, p_brand_id integer,
                                    p_dose_units numeric, p_doses_per_day numeric,
                                    p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text)
LANGUAGE sql STABLE AS $$
    WITH pt AS (
        SELECT fn_age_years(p.date_of_birth, p_on_date) AS age
        FROM patients p WHERE p.patient_id = p_patient_id
    ),
    lines AS (
        SELECT x.ingredient_id, x.daily_mg, false AS is_new
        FROM fn_patient_active_ingredients(p_patient_id, p_on_date) x
        UNION ALL
        SELECT e.ingredient_id, p_dose_units * p_doses_per_day * e.strength_mg, true
        FROM fn_expand_brand(p_brand_id) e
    ),
    totals AS (
        SELECT l.ingredient_id, l.is_new, l.daily_mg,
               SUM(l.daily_mg) OVER (PARTITION BY l.ingredient_id) AS total_mg
        FROM lines l
    )
    SELECT 'dose_limit'::check_type,
           CASE WHEN t.total_mg >= dl.max_daily_mg * 1.5 THEN 'critical'::severity_level
                ELSE 'major'::severity_level END,
           i.ingredient_id, i.name,
           NULL::integer, NULL::text,
           NULL::bigint,
           'Total daily dose of ' || i.name || ' would exceed the limit for this age band.',
           'Lower the dose or frequency, or stop other medicines that contain ' || i.name || '.',
           round(t.total_mg, 1)::text || ' mg/day in total (this prescription adds '
               || round(t.daily_mg, 1)::text || ' mg) against a limit of '
               || dl.max_daily_mg::text || ' mg/day, patient age ' || pt.age::text || '.',
           dl.source_id, s.name
    FROM totals t
    CROSS JOIN pt
    JOIN dose_limits dl
      ON dl.ingredient_id = t.ingredient_id
     AND pt.age >= dl.age_min_years AND pt.age < dl.age_max_years
    JOIN ingredients i  ON i.ingredient_id = t.ingredient_id
    LEFT JOIN sources s ON s.source_id = dl.source_id
    WHERE t.is_new
      AND t.total_mg > dl.max_daily_mg
$$;

-- ---------------------------------------------------------------------
-- Checks 1 to 4 together (no dose needed). Used by the alternatives search.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_core(p_patient_id bigint, p_brand_id integer, p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text)
LANGUAGE sql STABLE AS $$
    SELECT * FROM chk_duplicate(p_patient_id, p_brand_id, p_on_date)
    UNION ALL SELECT * FROM chk_interaction(p_patient_id, p_brand_id, p_on_date)
    UNION ALL SELECT * FROM chk_allergy(p_patient_id, p_brand_id, p_on_date)
    UNION ALL SELECT * FROM chk_contraindication(p_patient_id, p_brand_id, p_on_date)
$$;

-- ---------------------------------------------------------------------
-- Main entry point: all five checks, ranked.
-- Rank order: severity (critical first), then allergy, contraindication,
-- interaction, dose limit, duplicate.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_prescription(p_patient_id bigint, p_brand_id integer,
                                                 p_dose_units numeric, p_doses_per_day numeric,
                                                 p_on_date date DEFAULT current_date)
RETURNS TABLE(check_type check_type, severity severity_level,
              ingredient_id integer, ingredient_name text,
              related_ingredient_id integer, related_ingredient_name text,
              conflicting_item_id bigint, mechanism text, management text, detail text,
              source_id integer, source_name text, alert_rank integer)
LANGUAGE sql STABLE AS $$
    SELECT r.check_type, r.severity, r.ingredient_id, r.ingredient_name,
           r.related_ingredient_id, r.related_ingredient_name, r.conflicting_item_id,
           r.mechanism, r.management, r.detail, r.source_id, r.source_name,
           (ROW_NUMBER() OVER (
                ORDER BY r.severity DESC,
                         CASE r.check_type WHEN 'allergy' THEN 1 WHEN 'contraindication' THEN 2
                                           WHEN 'interaction' THEN 3 WHEN 'dose_limit' THEN 4
                                           ELSE 5 END,
                         r.ingredient_id, r.related_ingredient_id
           ))::integer AS alert_rank
    FROM (
        SELECT * FROM fn_check_core(p_patient_id, p_brand_id, p_on_date)
        UNION ALL
        SELECT * FROM chk_dose(p_patient_id, p_brand_id, p_dose_units, p_doses_per_day, p_on_date)
    ) r
    ORDER BY alert_rank
$$;

-- ---------------------------------------------------------------------
-- Safer alternatives
-- 1. Candidates: brands with an ingredient for the same indication as the flagged
--    brand (set logic: INTERSECT-style match on indication, EXCEPT the brand itself).
-- 2. Anti-join: keep a candidate only if NOT EXISTS a conflict of severity moderate
--    or worse (duplicate, interaction, allergy, contraindication) for this patient.
--    Minor interactions are allowed and counted.
-- 3. Rank with a window: lowest line of therapy first, then fewest minor
--    interactions, then name. The dose is not checked here: the doctor sets it
--    and fn_check_prescription then checks it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_safe_alternatives(p_patient_id bigint, p_brand_id integer,
                                                p_on_date date DEFAULT current_date,
                                                p_limit integer DEFAULT 10)
RETURNS TABLE(brand_id integer, brand_name text, manufacturer text, strength text,
              indication_name text, line_of_therapy smallint, minor_count integer, alt_rank integer)
LANGUAGE sql STABLE AS $$
    WITH target_ind AS (
        SELECT DISTINCT ii.indication_id
        FROM fn_expand_brand(p_brand_id) e
        JOIN ingredient_indications ii ON ii.ingredient_id = e.ingredient_id
    ),
    candidates AS (
        SELECT bi.brand_id
        FROM brand_ingredients bi
        JOIN ingredient_indications ii ON ii.ingredient_id = bi.ingredient_id
        WHERE ii.indication_id IN (SELECT t.indication_id FROM target_ind t)
        EXCEPT
        SELECT p_brand_id
    ),
    scored AS (
        SELECT c.brand_id,
               MIN(ii.line_of_therapy) AS line,
               MIN(ind.name)           AS indication_name
        FROM candidates c
        JOIN brand_ingredients bi ON bi.brand_id = c.brand_id
        JOIN ingredient_indications ii
          ON ii.ingredient_id = bi.ingredient_id
         AND ii.indication_id IN (SELECT t.indication_id FROM target_ind t)
        JOIN indications ind ON ind.indication_id = ii.indication_id
        GROUP BY c.brand_id
    ),
    safe AS (
        SELECT s.brand_id, s.line, s.indication_name,
               (SELECT count(*) FROM fn_check_core(p_patient_id, s.brand_id, p_on_date) k
                 WHERE k.severity = 'minor')::integer AS minor_count
        FROM scored s
        WHERE NOT EXISTS (
            SELECT 1 FROM fn_check_core(p_patient_id, s.brand_id, p_on_date) k
            WHERE k.severity >= 'moderate'
        )
    )
    SELECT b.brand_id, b.brand_name, b.manufacturer, b.strength,
           sf.indication_name, sf.line, sf.minor_count,
           (RANK() OVER (ORDER BY sf.line, sf.minor_count, b.brand_name))::integer AS alt_rank
    FROM safe sf
    JOIN brands b ON b.brand_id = sf.brand_id
    ORDER BY alt_rank, b.brand_name
    LIMIT p_limit
$$;

-- =====================================================================
-- End of 04_check_functions.sql
-- =====================================================================
