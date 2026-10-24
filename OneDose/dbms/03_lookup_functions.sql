-- File: dbms/03_lookup_functions.sql
-- Owner: Sivani  (only the owner edits this file)
-- Purpose: Helper functions: fn_class_descendants (recursive CTE over drug classes), fn_expand_brand (brand to ingredients), fn_search_brands (fuzzy brand search), fn_meds_as_of (medicines on a past date).
-- Inputs: Class id, brand id, search text, patient id and date.
-- Outputs: Rows for the checks and the API.
-- Depends on: 01_schema.sql, 02_seed_reference.sql

-- ---------------------------------------------------------------------
-- fn_class_descendants:
-- Traverses the self-referencing drug_classes tree to resolve all child and
-- descendant subclasses for a given parent class. Used by allergy and class-interaction
-- checks to propagate safety rules down the pharmacological taxonomy.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_class_descendants(p_class_id integer)
RETURNS TABLE(class_id integer)
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE hierarchy AS (
        SELECT dc.class_id, 1 AS depth
        FROM drug_classes dc
        WHERE dc.class_id = p_class_id
        UNION ALL
        SELECT dc.class_id, h.depth + 1
        FROM drug_classes dc
        JOIN hierarchy h ON dc.parent_class_id = h.class_id
        WHERE h.depth < 20
    )
    SELECT hierarchy.class_id FROM hierarchy;
$$;

COMMENT ON FUNCTION fn_class_descendants(integer) IS
'Recursively retrieves a drug class and all its descendant subclasses with cycle protection.';

-- ---------------------------------------------------------------------
-- fn_expand_brand:
-- Decomposes a commercial brand medication into its underlying active chemical
-- ingredients and unit strengths (mg). Core primitive for ingredient-level safety checks.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expand_brand(p_brand_id integer)
RETURNS TABLE(
    ingredient_id integer,
    ingredient_name text,
    strength_mg numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        i.ingredient_id,
        i.name AS ingredient_name,
        bi.strength_mg
    FROM brand_ingredients bi
    JOIN ingredients i ON i.ingredient_id = bi.ingredient_id
    WHERE bi.brand_id = p_brand_id
    ORDER BY i.name ASC;
$$;

COMMENT ON FUNCTION fn_expand_brand(integer) IS
'Expands a brand into its active pharmaceutical ingredients and unit strength in mg.';

-- ---------------------------------------------------------------------
-- fn_search_brands:
-- Performs resilient fuzzy brand name searching with input normalization
-- (stripping spaces, hyphens, and case differences) using pg_trgm similarity
-- and prefix boosting. Returns brand metadata with nested active ingredients JSON.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_search_brands(p_query text, p_limit int DEFAULT 10)
RETURNS TABLE(
    brand_id integer,
    brand_name text,
    form text,
    strength text,
    match_score real,
    ingredients jsonb
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_clean_query text;
BEGIN
    v_clean_query := regexp_replace(lower(coalesce(p_query, '')), '[\s\-]+', '', 'g');

    RETURN QUERY
    SELECT
        b.brand_id,
        b.brand_name,
        b.form,
        b.strength,
        (
            similarity(regexp_replace(lower(b.brand_name), '[\s\-]+', '', 'g'), v_clean_query)
            + CASE
                WHEN regexp_replace(lower(b.brand_name), '[\s\-]+', '', 'g') LIKE (v_clean_query || '%') THEN 0.5::real
                WHEN lower(b.brand_name) LIKE (lower(p_query) || '%') THEN 0.3::real
                ELSE 0.0::real
              END
        )::real AS match_score,
        coalesce(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'ingredient_id', bi.ingredient_id,
                        'name', i.name,
                        'strength_mg', bi.strength_mg
                    ) ORDER BY i.name ASC
                )
                FROM brand_ingredients bi
                JOIN ingredients i ON i.ingredient_id = bi.ingredient_id
                WHERE bi.brand_id = b.brand_id
            ),
            '[]'::jsonb
        ) AS ingredients
    FROM brands b
    WHERE length(v_clean_query) > 0
      AND (
          similarity(regexp_replace(lower(b.brand_name), '[\s\-]+', '', 'g'), v_clean_query) > 0.15
          OR regexp_replace(lower(b.brand_name), '[\s\-]+', '', 'g') LIKE ('%' || v_clean_query || '%')
          OR lower(b.brand_name) LIKE ('%' || lower(p_query) || '%')
      )
    ORDER BY match_score DESC, b.brand_name ASC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION fn_search_brands(text, int) IS
'Normalised fuzzy brand lookup using trigram similarity and prefix boosting with embedded ingredients.';

-- ---------------------------------------------------------------------
-- fn_meds_as_of:
-- Computes the patient medication history active on a specific historical or current date,
-- expanding each prescription item into its component active ingredients and calculating
-- total daily intake (dose_units * doses_per_day * strength_mg).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meds_as_of(p_patient_id bigint, p_as_of date)
RETURNS TABLE(
    prescription_item_id bigint,
    brand_id integer,
    brand_name text,
    ingredient_id integer,
    ingredient_name text,
    strength_mg numeric,
    daily_ingredient_mg numeric,
    start_date date,
    end_date date
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pi.item_id AS prescription_item_id,
        b.brand_id,
        b.brand_name,
        i.ingredient_id,
        i.name AS ingredient_name,
        bi.strength_mg,
        round(bi.strength_mg * pi.dose_units * pi.doses_per_day, 3) AS daily_ingredient_mg,
        pi.start_date,
        pi.end_date
    FROM prescription_items pi
    JOIN brands b ON b.brand_id = pi.brand_id
    JOIN brand_ingredients bi ON bi.brand_id = pi.brand_id
    JOIN ingredients i ON i.ingredient_id = bi.ingredient_id
    WHERE pi.patient_id = p_patient_id
      AND pi.start_date <= p_as_of
      AND (pi.end_date IS NULL OR pi.end_date >= p_as_of)
    ORDER BY pi.start_date DESC, b.brand_name ASC, i.name ASC;
$$;

COMMENT ON FUNCTION fn_meds_as_of(bigint, date) IS
'Calculates the active pharmaceutical ingredients and daily intake for a patient as of a specific date.';
