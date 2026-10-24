-- File: dbms/05_views.sql
-- Owner: Sivani  (only the owner edits this file)
-- Purpose: Read-only views for the API: v_active_medications, v_patient_summary, an alert-statistics view (override rate per check) and v_audit_recent.
-- Inputs: Tables.
-- Outputs: Views the backend reads.
-- Depends on: 01_schema.sql

-- =====================================================================
-- 1. v_active_medications
-- Backend Contract:
--   patient_id            bigint
--   prescription_item_id  bigint
--   brand_id              integer
--   brand_name            text
--   ingredient_id         integer
--   ingredient_name       text
--   strength_mg           numeric(10,3)
--   daily_ingredient_mg   numeric
--   start_date            date
--   end_date              date
-- Returns currently active prescription items expanded to active ingredients.
-- =====================================================================
DROP VIEW IF EXISTS v_active_medications CASCADE;

CREATE VIEW v_active_medications AS
SELECT
    pi.patient_id,
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
WHERE pi.start_date <= current_date
  AND (pi.end_date IS NULL OR pi.end_date >= current_date);

-- =====================================================================
-- 2. v_patient_summary
-- Backend Contract:
--   patient_id            bigint
--   display_name          text
--   age_years             integer
--   active_ingredients    jsonb
--   allergies             jsonb
--   conditions            jsonb
--   has_active_consent    boolean
--   consent_expires_at    timestamptz
-- Provides a consolidated real-time clinical snapshot for a patient.
-- =====================================================================
DROP VIEW IF EXISTS v_patient_summary CASCADE;

CREATE VIEW v_patient_summary AS
SELECT
    p.patient_id,
    p.full_name AS display_name,
    fn_age_years(p.date_of_birth, current_date) AS age_years,
    coalesce(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'ingredient_id', vam.ingredient_id,
                    'ingredient_name', vam.ingredient_name,
                    'brand_name', vam.brand_name,
                    'daily_ingredient_mg', vam.daily_ingredient_mg
                ) ORDER BY vam.ingredient_name ASC
            )
            FROM v_active_medications vam
            WHERE vam.patient_id = p.patient_id
        ),
        '[]'::jsonb
    ) AS active_ingredients,
    coalesce(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'allergy_id', pa.allergy_id,
                    'ingredient_id', pa.ingredient_id,
                    'ingredient_name', i.name,
                    'class_id', pa.class_id,
                    'class_name', dc.name,
                    'reaction', pa.reaction,
                    'severity', pa.severity
                ) ORDER BY pa.allergy_id ASC
            )
            FROM patient_allergies pa
            LEFT JOIN ingredients i ON i.ingredient_id = pa.ingredient_id
            LEFT JOIN drug_classes dc ON dc.class_id = pa.class_id
            WHERE pa.patient_id = p.patient_id
              AND pa.valid_from <= current_date
              AND (pa.valid_to IS NULL OR pa.valid_to >= current_date)
        ),
        '[]'::jsonb
    ) AS allergies,
    coalesce(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'patient_condition_id', pc.patient_condition_id,
                    'condition_id', c.condition_id,
                    'condition_name', c.name,
                    'icd10_code', c.icd10_code,
                    'valid_from', pc.valid_from
                ) ORDER BY c.name ASC
            )
            FROM patient_conditions pc
            JOIN conditions c ON c.condition_id = pc.condition_id
            WHERE pc.patient_id = p.patient_id
              AND pc.valid_from <= current_date
              AND (pc.valid_to IS NULL OR pc.valid_to >= current_date)
        ),
        '[]'::jsonb
    ) AS conditions,
    coalesce(lc.has_active_consent, false) AS has_active_consent,
    lc.expires_at AS consent_expires_at
FROM patients p
LEFT JOIN LATERAL (
    SELECT
        c.expires_at,
        (c.expires_at > now() AND c.revoked_at IS NULL) AS has_active_consent
    FROM consents c
    WHERE c.patient_id = p.patient_id
    ORDER BY c.granted_at DESC, c.consent_id DESC
    LIMIT 1
) lc ON true;

-- =====================================================================
-- 3. mv_alert_stats and fn_refresh_alert_stats
-- Backend Contract:
--   check_type            check_type
--   total_alerts          bigint
--   overridden_alerts     bigint
--   override_rate_pct     numeric
-- Aggregates alert override frequencies without divide-by-zero risks.
-- =====================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_alert_stats CASCADE;

CREATE MATERIALIZED VIEW mv_alert_stats AS
SELECT
    ct.check_type,
    coalesce(count(a.alert_id), 0)::bigint AS total_alerts,
    coalesce(count(a.alert_id) FILTER (WHERE a.status = 'overridden'), 0)::bigint AS overridden_alerts,
    coalesce(
        round(
            (count(a.alert_id) FILTER (WHERE a.status = 'overridden')::numeric / NULLIF(count(a.alert_id), 0)::numeric) * 100.0,
            2
        ),
        0.00
    ) AS override_rate_pct
FROM (
    SELECT unnest(enum_range(NULL::check_type)) AS check_type
) ct
LEFT JOIN alerts a ON a.check_type = ct.check_type
GROUP BY ct.check_type
ORDER BY ct.check_type ASC;

CREATE OR REPLACE FUNCTION fn_refresh_alert_stats()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_alert_stats;
END;
$$;

COMMENT ON FUNCTION fn_refresh_alert_stats() IS
'Refreshes the materialized view mv_alert_stats aggregating safety alert frequencies.';

-- =====================================================================
-- 4. v_audit_recent
-- Backend Contract:
--   audit_id              bigint
--   occurred_at           timestamptz
--   actor                 text
--   action                text
--   table_name            text
--   row_id                text
--   hash_prefix           text
-- Returns the 200 most recent tamper-evident audit entries.
-- Note: Maps real column row_pk from audit_log to contract column row_id.
-- =====================================================================
DROP VIEW IF EXISTS v_audit_recent CASCADE;

CREATE VIEW v_audit_recent AS
SELECT
    al.audit_id,
    al.occurred_at,
    al.actor,
    al.action,
    al.table_name,
    al.row_pk AS row_id,
    substr(encode(al.row_hash, 'hex'), 1, 8) AS hash_prefix
FROM audit_log al
ORDER BY al.occurred_at DESC, al.audit_id DESC
LIMIT 200;
