-- File: dbms/09_patient_portal.sql
-- Owner: Bhavya
-- Purpose: Everything the patient portal needs from the database, in one re-runnable file:
--   * patient_logins        email + bcrypt password per patient (the API never reads hashes; fn_patient_login checks them)
--   * self_reported_meds    store-bought medicines a patient reports. Kept OUT of prescription_items on purpose, so
--                           unverified data can never feed the safety checks or the "active medicines" views.
--   * fn_patient_login      password check inside the database (same idea as fn_login in 08)
--   * fn_portal_grant_consent / fn_portal_revoke_consent   the patient controls their own consent
--   * fn_portal_access_log  "who viewed my record" (reads the hash-chained audit log, own record only)
--   * fn_portal_symptom_search   the patient's past medicines for a symptom, with dates, dose and prescriber
--   * fn_self_reported_rows self-reported medicines + allergy match (patient: own rows; clinician: needs consent)
--   Row-level security and grants for the onedose_patient role, and demo logins for demo patients 1 to 7.
-- Inputs: none
-- Outputs: New tables, functions and policies.
-- Depends on: 01 to 08 (run it AFTER 08)
--
-- Notes
--   * Re-runnable. 08_security.sql wipes every grant and policy when it runs, so if you ever re-run 08 (or 05),
--     run this file again afterwards.
--   * The SECURITY DEFINER functions run as the table owner (row security does not apply), so each one filters by
--     fn_current_patient_id() / fn_has_consent() itself.
--   * Demo patient logins are public and synthetic: patient1@onedose.local ... patient7@onedose.local / patient123.
--     Change or delete them before sharing the link widely.

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_logins (
    patient_id    bigint PRIMARY KEY REFERENCES patients(patient_id),
    email         text NOT NULL UNIQUE,
    password_hash text NOT NULL,                     -- bcrypt via pgcrypto crypt()
    active        boolean NOT NULL DEFAULT true,
    CONSTRAINT patient_logins_email_lower CHECK (email = lower(email))
);

CREATE TABLE IF NOT EXISTS self_reported_meds (
    report_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id     bigint NOT NULL REFERENCES patients(patient_id),
    brand_id       integer REFERENCES brands(brand_id),     -- picked from the brand list (can be allergy-checked)
    free_text_name text,                                     -- typed name (cannot be checked)
    doses_per_day  numeric(5,2) CHECK (doses_per_day > 0),
    note           text,
    started_on     date NOT NULL DEFAULT current_date,
    stopped_on     date,
    reported_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT srm_one_target CHECK ((brand_id IS NULL) <> (free_text_name IS NULL)),
    CONSTRAINT srm_name_len   CHECK (free_text_name IS NULL OR length(btrim(free_text_name)) BETWEEN 2 AND 80),
    CONSTRAINT srm_note_len   CHECK (note IS NULL OR length(note) <= 300),
    CONSTRAINT srm_dates      CHECK (stopped_on IS NULL OR stopped_on >= started_on)
);
CREATE INDEX IF NOT EXISTS idx_srm_patient ON self_reported_meds (patient_id, reported_at DESC);

DROP TRIGGER IF EXISTS trg_audit_self_reported ON self_reported_meds;
CREATE TRIGGER trg_audit_self_reported AFTER INSERT OR UPDATE OR DELETE ON self_reported_meds
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('report_id');

-- ---------------------------------------------------------------------
-- 2. Functions
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_patient_login(p_email text, p_password text)
RETURNS TABLE(patient_id bigint, full_name text, db_username text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT p.patient_id, p.full_name, p.db_username
    FROM patient_logins l
    JOIN patients p ON p.patient_id = l.patient_id
    WHERE l.active AND p.db_username IS NOT NULL
      AND l.email = lower(btrim(p_email))
      AND l.password_hash = crypt(p_password, l.password_hash)
$$;

-- The patient withdraws access: every active consent of theirs is revoked (clinicians lose access at once).
CREATE OR REPLACE FUNCTION fn_portal_revoke_consent() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_pid bigint := fn_current_patient_id();
    v_n   integer;
BEGIN
    IF v_pid IS NULL THEN
        RAISE EXCEPTION 'not a patient session' USING ERRCODE = 'insufficient_privilege';
    END IF;
    UPDATE consents SET revoked_at = now()
    WHERE patient_id = v_pid AND revoked_at IS NULL AND expires_at > now();
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;

-- The patient allows access again: a new consent row (the latest consent wins, see fn_has_consent).
CREATE OR REPLACE FUNCTION fn_portal_grant_consent(p_days integer DEFAULT 365) RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_pid bigint := fn_current_patient_id();
    v_exp timestamptz;
BEGIN
    IF v_pid IS NULL THEN
        RAISE EXCEPTION 'not a patient session' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF p_days IS NULL OR p_days < 1 OR p_days > 365 THEN
        RAISE EXCEPTION 'days must be between 1 and 365' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    INSERT INTO consents (patient_id, scope, granted_at, expires_at)
    VALUES (v_pid, 'treatment', now(), now() + make_interval(days => p_days))
    RETURNING expires_at INTO v_exp;
    RETURN v_exp;
END $$;

-- Who looked at MY record (staff reads written by fn_log_read, and prescriptions written for me).
CREATE OR REPLACE FUNCTION fn_portal_access_log(p_limit integer DEFAULT 50)
RETURNS TABLE(occurred_at timestamptz, who text, staff_role text, what text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT a.occurred_at,
           coalesce(c.full_name, 'Hospital system'),
           coalesce(c.role::text, 'system'),
           CASE a.table_name
                WHEN 'patients'           THEN 'Opened your record'
                WHEN 'prescription_items' THEN 'Viewed your medicines'
                WHEN 'self_reported_meds' THEN 'Viewed the medicines you reported'
                WHEN 'prescriptions'      THEN 'Added a prescription'
           END
    FROM audit_log a
    LEFT JOIN clinicians c ON c.db_username = a.actor
    WHERE fn_current_patient_id() IS NOT NULL
      AND ( (a.action = 'READ'
             AND a.table_name IN ('patients', 'prescription_items', 'self_reported_meds')
             AND a.row_pk = fn_current_patient_id()::text)
         OR (a.action = 'INSERT' AND a.table_name = 'prescriptions'
             AND a.new_data ->> 'patient_id' = fn_current_patient_id()::text) )
    ORDER BY a.occurred_at DESC, a.audit_id DESC
    LIMIT least(greatest(coalesce(p_limit, 50), 1), 200)
$$;

-- "What did I take for fever?" One row per prescription item whose ingredients are used for the symptom.
CREATE OR REPLACE FUNCTION fn_portal_symptom_search(p_symptom text)
RETURNS TABLE(item_id bigint, brand_name text, ingredients text, indication text,
              dose_units numeric, doses_per_day numeric, start_date date, end_date date, prescriber text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT pi.item_id, b.brand_name,
           string_agg(DISTINCT i.name, ', ' ORDER BY i.name),
           string_agg(DISTINCT ind.name, ', ' ORDER BY ind.name),
           pi.dose_units, pi.doses_per_day, pi.start_date, pi.end_date, cl.full_name
    FROM prescription_items pi
    JOIN prescriptions rx          ON rx.prescription_id = pi.prescription_id
    JOIN clinicians cl             ON cl.clinician_id = rx.clinician_id
    JOIN brands b                  ON b.brand_id = pi.brand_id
    JOIN brand_ingredients bi      ON bi.brand_id = pi.brand_id
    JOIN ingredients i             ON i.ingredient_id = bi.ingredient_id
    JOIN ingredient_indications ii ON ii.ingredient_id = bi.ingredient_id
    JOIN indications ind           ON ind.indication_id = ii.indication_id
    WHERE pi.patient_id = fn_current_patient_id()
      AND length(btrim(p_symptom)) >= 2
      AND position(lower(btrim(p_symptom)) IN lower(ind.name)) > 0
    GROUP BY pi.item_id, b.brand_name, pi.dose_units, pi.doses_per_day, pi.start_date, pi.end_date, cl.full_name
    ORDER BY pi.start_date DESC, pi.item_id DESC
    LIMIT 100
$$;

-- Self-reported medicines of one patient, each with its allergy match (existing chk_allergy, brand picks only).
-- A patient may read only their own; a clinician only for a patient with an active consent.
CREATE OR REPLACE FUNCTION fn_self_reported_rows(p_patient_id bigint)
RETURNS TABLE(report_id bigint, brand_id integer, medicine text, form_strength text, doses_per_day numeric,
              note text, started_on date, stopped_on date, reported_at timestamptz,
              checked boolean, allergy_match boolean, allergy_ingredients text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT s.report_id, s.brand_id, coalesce(b.brand_name, s.free_text_name), b.strength, s.doses_per_day,
           s.note, s.started_on, s.stopped_on, s.reported_at,
           s.brand_id IS NOT NULL,
           EXISTS (SELECT 1 FROM chk_allergy(s.patient_id, s.brand_id, current_date)),
           (SELECT string_agg(DISTINCT a.ingredient_name, ', ') FROM chk_allergy(s.patient_id, s.brand_id, current_date) a)
    FROM self_reported_meds s
    LEFT JOIN brands b ON b.brand_id = s.brand_id
    WHERE s.patient_id = p_patient_id
      AND ( p_patient_id = fn_current_patient_id()
            OR (fn_current_clinician_id() IS NOT NULL AND fn_has_consent(p_patient_id)) )
    ORDER BY (s.stopped_on IS NULL) DESC, s.reported_at DESC, s.report_id DESC
$$;

-- ---------------------------------------------------------------------
-- 3. Row-level security and grants (08 has already run)
-- ---------------------------------------------------------------------
ALTER TABLE self_reported_meds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS srm_pat_sel ON self_reported_meds;
DROP POLICY IF EXISTS srm_pat_ins ON self_reported_meds;
DROP POLICY IF EXISTS srm_pat_upd ON self_reported_meds;
CREATE POLICY srm_pat_sel ON self_reported_meds FOR SELECT TO onedose_patient
    USING (patient_id = fn_current_patient_id());
CREATE POLICY srm_pat_ins ON self_reported_meds FOR INSERT TO onedose_patient
    WITH CHECK (patient_id = fn_current_patient_id());
CREATE POLICY srm_pat_upd ON self_reported_meds FOR UPDATE TO onedose_patient
    USING (patient_id = fn_current_patient_id()) WITH CHECK (patient_id = fn_current_patient_id());

REVOKE ALL ON patient_logins, self_reported_meds FROM PUBLIC;
GRANT SELECT, INSERT ON self_reported_meds TO onedose_patient;
GRANT UPDATE (stopped_on) ON self_reported_meds TO onedose_patient;   -- "I stopped taking it"

REVOKE EXECUTE ON FUNCTION fn_patient_login(text, text), fn_portal_revoke_consent(), fn_portal_grant_consent(integer),
                           fn_portal_access_log(integer), fn_portal_symptom_search(text), fn_self_reported_rows(bigint)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_patient_login(text, text) TO onedose_api;
GRANT EXECUTE ON FUNCTION fn_portal_revoke_consent(), fn_portal_grant_consent(integer), fn_portal_access_log(integer),
                          fn_portal_symptom_search(text) TO onedose_patient;
GRANT EXECUTE ON FUNCTION fn_self_reported_rows(bigint) TO onedose_patient, onedose_clinician;
-- the portal reuses two existing read functions (they run as the patient, so row security still applies)
GRANT EXECUTE ON FUNCTION fn_meds_as_of(bigint, date), fn_search_brands(text, integer) TO onedose_patient;

-- ---------------------------------------------------------------------
-- 4. Demo logins for demo patients 1 to 7 (skipped if those patients do not exist)
-- ---------------------------------------------------------------------
UPDATE patients SET db_username = 'patient_' || patient_id
WHERE patient_id BETWEEN 1 AND 7 AND db_username IS NULL;

INSERT INTO patient_logins (patient_id, email, password_hash)
SELECT p.patient_id, 'patient' || p.patient_id || '@onedose.local', crypt('patient123', gen_salt('bf'))
FROM patients p
WHERE p.patient_id BETWEEN 1 AND 7
ON CONFLICT (patient_id) DO NOTHING;

-- =====================================================================
-- End of 09_patient_portal.sql
-- =====================================================================
