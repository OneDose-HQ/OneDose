-- File: dbms/08_security.sql
-- Owner: Bhavya  (only the owner edits this file)
-- Purpose: Who can see and do what: roles (clinician, pharmacist, patient, admin), GRANT and REVOKE, access limited to patients with an unexpired consent, masked view for pharmacists.
--   Roles (all NOLOGIN groups): onedose_clinician, onedose_pharmacist, onedose_patient, onedose_admin, onedose_scanner.
--   onedose_api is the ONE login the backend uses. It has no rights of its own: per request db.py runs
--       BEGIN;  SET LOCAL ROLE onedose_clinician;  SELECT set_config('onedose.user', '<db_username>', true);  ...  COMMIT;
--   Least privilege in short:
--     clinician  reads/writes patient data ONLY for patients with an active consent (row-level security); cannot touch
--                alerts except to resolve them, cannot read audit_log, cannot read password hashes.
--     pharmacist read-only; sees patients only through v_pharmacist_patients (masked name, no date of birth).
--     patient    sees only their own rows.
--     admin      manages reference data, accounts, cards, devices; reads audit_log and statistics; NO patient records.
--     scanner    can only call fn_record_scan (the card reader path).
--   Supporting functions: fn_has_consent, fn_current_clinician_id, fn_current_patient_id (used by the policies),
--   fn_login (password check inside the DB), fn_record_scan, view v_latest_scan, view v_pharmacist_patients,
--   fn_alert_severity_counts and fn_top_overridden (aggregates for the analytics page).
-- Inputs: none
-- Outputs: Roles and access rules.
-- Depends on: 01_schema.sql, 04_check_functions.sql, 05_views.sql, 07_triggers.sql
--
-- Notes
--   * Re-runnable. If 05_views.sql is re-run, run this file again (05 drops and recreates the views).
--   * Set the login password outside git:  ALTER ROLE onedose_api PASSWORD '<value of DB_PASSWORD in .env>';
--   * Row security is not applied to the table owner or a superuser (seeds, benchmarks, SECURITY DEFINER triggers).
--   * fn_check_prescription runs as the caller, so for a patient without consent it sees NO data and returns no alerts.
--     The API must therefore check fn_has_consent first; writes for such a patient are refused by the policies anyway.
--   * 'onedose.user' is trusted because the API is the only way in. It decides which clinician/patient a session is.

-- ---------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['onedose_clinician', 'onedose_pharmacist', 'onedose_patient',
                             'onedose_admin', 'onedose_scanner'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'onedose_api') THEN
        CREATE ROLE onedose_api LOGIN NOINHERIT;
    END IF;
END $$;

ALTER ROLE onedose_api NOINHERIT;
GRANT onedose_clinician, onedose_pharmacist, onedose_patient, onedose_admin, onedose_scanner TO onedose_api;

-- ---------------------------------------------------------------------
-- 2. Identity and consent helpers (SECURITY DEFINER: they must see rows the caller cannot)
-- ---------------------------------------------------------------------
-- Latest consent wins (same rule as v_patient_summary): valid, not expired, not revoked.
CREATE OR REPLACE FUNCTION fn_has_consent(p_patient_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT coalesce((SELECT c.expires_at > now() AND c.revoked_at IS NULL
                     FROM consents c WHERE c.patient_id = p_patient_id
                     ORDER BY c.granted_at DESC, c.consent_id DESC LIMIT 1), false)
$$;

CREATE OR REPLACE FUNCTION fn_current_clinician_id() RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT c.clinician_id FROM clinicians c
    WHERE c.active AND c.db_username = nullif(current_setting('onedose.user', true), '')
$$;

CREATE OR REPLACE FUNCTION fn_current_patient_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT p.patient_id FROM patients p
    WHERE p.db_username = nullif(current_setting('onedose.user', true), '')
$$;

-- Password check stays in the database: the API never reads password hashes.
-- (Seed hashes come from pgcrypto crypt(), bcrypt $2a$.) Add rate limiting in the API.
CREATE OR REPLACE FUNCTION fn_login(p_username text, p_password text)
RETURNS TABLE(clinician_id integer, full_name text, role clinician_role, db_username text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT c.clinician_id, c.full_name, c.role, c.db_username
    FROM clinicians c
    WHERE c.active AND c.password_hash IS NOT NULL
      AND (c.db_username = p_username OR c.email = p_username)
      AND c.password_hash = crypt(p_password, c.password_hash)
$$;

-- Card reader path. The API checks the device key, then calls this with the SHA-256 of the UID.
-- Records the scan and says what happened. patient_id is returned only when outcome = 'matched'.
CREATE OR REPLACE FUNCTION fn_record_scan(p_uid_hash bytea, p_device_name text DEFAULT NULL)
RETURNS TABLE(scan_id bigint, outcome text, patient_id bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
#variable_conflict use_column
DECLARE
    v_dev integer; v_card bigint; v_patient bigint; v_active boolean; v_outcome text; v_scan bigint;
BEGIN
    IF p_uid_hash IS NULL OR octet_length(p_uid_hash) <> 32 THEN
        RAISE EXCEPTION 'uid hash must be 32 bytes (SHA-256)' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_device_name IS NOT NULL THEN
        SELECT d.device_id INTO v_dev FROM devices d WHERE d.name = p_device_name;
        IF v_dev IS NULL THEN
            RAISE EXCEPTION 'unknown device %', p_device_name USING ERRCODE = 'invalid_parameter_value';
        END IF;
        UPDATE devices SET last_seen_at = now() WHERE device_id = v_dev;
    END IF;

    SELECT c.card_id, c.patient_id, c.active INTO v_card, v_patient, v_active
    FROM rfid_cards c WHERE c.uid_hash = p_uid_hash;

    v_outcome := CASE WHEN v_card IS NULL THEN 'unknown_card'
                      WHEN NOT v_active THEN 'inactive_card'
                      WHEN NOT fn_has_consent(v_patient) THEN 'no_consent'
                      ELSE 'matched' END;

    INSERT INTO card_scans (device_id, card_id, uid_hash, outcome)
    VALUES (v_dev, v_card, p_uid_hash, v_outcome) RETURNING card_scans.scan_id INTO v_scan;

    RETURN QUERY SELECT v_scan, v_outcome,
                        CASE WHEN v_outcome = 'matched' THEN v_patient ELSE NULL::bigint END;
END $$;

-- The newest successful tap in the last 2 minutes (the dashboard polls this)
CREATE OR REPLACE VIEW v_latest_scan AS
SELECT s.scan_id, s.scanned_at, c.patient_id
FROM card_scans s
JOIN rfid_cards c ON c.card_id = s.card_id
WHERE s.outcome = 'matched'
  AND s.scanned_at > now() - interval '2 minutes'
  AND fn_has_consent(c.patient_id)
ORDER BY s.scanned_at DESC, s.scan_id DESC
LIMIT 1;

-- ---------------------------------------------------------------------
-- 3. Views: run as the CALLER so row security applies (05's views default to owner rights)
--    The pharmacist view is the opposite on purpose: it runs as owner, filters consent itself, masks the name
--    (initials only) and leaves out date of birth, weight and sex.
-- ---------------------------------------------------------------------
ALTER VIEW v_active_medications SET (security_invoker = true);
ALTER VIEW v_patient_summary    SET (security_invoker = true);

-- It reads the base tables itself: a security_invoker view nested inside it would still check the pharmacist.
DROP VIEW IF EXISTS v_pharmacist_patients;
CREATE VIEW v_pharmacist_patients AS
SELECT p.patient_id,
       (SELECT string_agg(left(w, 1) || '.', ' ') FROM regexp_split_to_table(p.full_name, '\s+') AS w) AS masked_name,
       fn_age_years(p.date_of_birth, current_date) AS age_years,
       coalesce((SELECT jsonb_agg(jsonb_build_object(
                    'ingredient_id', i.ingredient_id, 'ingredient_name', i.name, 'brand_name', b.brand_name,
                    'daily_ingredient_mg', round(bi.strength_mg * pi.dose_units * pi.doses_per_day, 3))
                    ORDER BY i.name)
                 FROM prescription_items pi
                 JOIN brands b             ON b.brand_id = pi.brand_id
                 JOIN brand_ingredients bi ON bi.brand_id = pi.brand_id
                 JOIN ingredients i        ON i.ingredient_id = bi.ingredient_id
                 WHERE pi.patient_id = p.patient_id AND pi.active_period @> current_date), '[]'::jsonb) AS active_ingredients,
       coalesce((SELECT jsonb_agg(jsonb_build_object(
                    'ingredient_name', i.name, 'class_name', dc.name, 'reaction', pa.reaction, 'severity', pa.severity)
                    ORDER BY pa.allergy_id)
                 FROM patient_allergies pa
                 LEFT JOIN ingredients i   ON i.ingredient_id = pa.ingredient_id
                 LEFT JOIN drug_classes dc ON dc.class_id = pa.class_id
                 WHERE pa.patient_id = p.patient_id AND pa.valid_from <= current_date
                   AND (pa.valid_to IS NULL OR pa.valid_to > current_date)), '[]'::jsonb) AS allergies,
       coalesce((SELECT jsonb_agg(jsonb_build_object('condition_name', c.name, 'icd10_code', c.icd10_code)
                    ORDER BY c.name)
                 FROM patient_conditions pc
                 JOIN conditions c ON c.condition_id = pc.condition_id
                 WHERE pc.patient_id = p.patient_id AND pc.valid_from <= current_date
                   AND (pc.valid_to IS NULL OR pc.valid_to > current_date)), '[]'::jsonb) AS conditions,
       (SELECT k.expires_at FROM consents k WHERE k.patient_id = p.patient_id
        ORDER BY k.granted_at DESC, k.consent_id DESC LIMIT 1) AS consent_expires_at
FROM patients p
WHERE fn_has_consent(p.patient_id);

-- Alert analytics for the dashboard. Aggregates only, no patient identity, so clinicians may read them too.
CREATE OR REPLACE FUNCTION fn_alert_severity_counts()
RETURNS TABLE(severity severity_level, alert_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT s.sev, count(a.alert_id)
    FROM (SELECT unnest(enum_range(NULL::severity_level)) AS sev) s
    LEFT JOIN alerts a ON a.severity = s.sev
    GROUP BY s.sev ORDER BY s.sev DESC
$$;

CREATE OR REPLACE FUNCTION fn_top_overridden(p_limit integer DEFAULT 5)
RETURNS TABLE(ingredient_pair text, check_type check_type, override_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT CASE WHEN r.name IS NULL THEN i.name ELSE i.name || ' × ' || r.name END,
           a.check_type, count(*)
    FROM alerts a
    JOIN ingredients i      ON i.ingredient_id = a.ingredient_id
    LEFT JOIN ingredients r ON r.ingredient_id = a.related_ingredient_id
    WHERE a.status = 'overridden'
    GROUP BY 1, 2
    ORDER BY count(*) DESC, 1
    LIMIT greatest(p_limit, 1)
$$;

-- 05's refresh function must be able to REFRESH a materialized view the admin does not own
ALTER FUNCTION fn_refresh_alert_stats() SECURITY DEFINER SET search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 4. Clean slate, then grants
-- ---------------------------------------------------------------------
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, onedose_clinician, onedose_pharmacist,
                                               onedose_patient, onedose_admin, onedose_scanner, onedose_api;
DO $$ BEGIN EXECUTE format('GRANT CONNECT ON DATABASE %I TO onedose_api', current_database()); END $$;
GRANT USAGE ON SCHEMA public TO onedose_clinician, onedose_pharmacist, onedose_patient, onedose_admin, onedose_scanner;

-- Functions: nothing is callable by PUBLIC except extension functions (similarity, digest, crypt ...)
DO $$
DECLARE f regprocedure;
BEGIN
    FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace
               AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, onedose_clinician, onedose_pharmacist, onedose_patient, onedose_admin, onedose_scanner, onedose_api', f);
    END LOOP;
END $$;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Helper for the grants below: grant EXECUTE on functions by name
CREATE OR REPLACE FUNCTION pg_temp.grant_exec(p_role text, p_names text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE f regprocedure;
BEGIN
    FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (p_names)
    LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I', f, p_role);
    END LOOP;
END $$;

-- 4a. Reference (drug knowledge and rules): everyone who works with drugs may read it
GRANT SELECT ON sources, ingredients, drug_classes, ingredient_classes, brands, brand_ingredients,
                indications, ingredient_indications, conditions, interactions, class_interactions,
                contraindications, dose_limits
    TO onedose_clinician, onedose_pharmacist, onedose_patient, onedose_admin;
GRANT INSERT, UPDATE, DELETE ON sources, ingredients, drug_classes, ingredient_classes, brands,
                brand_ingredients, indications, ingredient_indications, conditions, interactions,
                class_interactions, contraindications, dose_limits TO onedose_admin;

-- 4b. Clinician
GRANT SELECT ON patients, patient_allergies, patient_conditions, prescriptions, prescription_items,
                alerts, consents TO onedose_clinician;
GRANT INSERT ON prescriptions, prescription_items, patient_allergies, patient_conditions, consents TO onedose_clinician;
GRANT UPDATE (end_date)  ON prescription_items TO onedose_clinician;
GRANT UPDATE (valid_to)  ON patient_allergies, patient_conditions TO onedose_clinician;
GRANT UPDATE (revoked_at) ON consents TO onedose_clinician;
GRANT UPDATE (status, override_reason, resolved_by, resolved_at, explanation) ON alerts TO onedose_clinician;
GRANT SELECT ON v_active_medications, v_patient_summary, v_latest_scan, mv_alert_stats TO onedose_clinician;
SELECT pg_temp.grant_exec('onedose_clinician', ARRAY[
    'fn_refresh_alert_stats', 'fn_alert_severity_counts', 'fn_top_overridden',
    'fn_age_years', 'fn_class_descendants', 'fn_expand_brand', 'fn_search_brands', 'fn_meds_as_of',
    'fn_patient_active_ingredients', 'fn_in_class_tree', 'chk_duplicate', 'chk_interaction', 'chk_allergy',
    'chk_contraindication', 'chk_dose', 'fn_check_core', 'fn_check_prescription', 'fn_safe_alternatives',
    'fn_has_consent', 'fn_current_clinician_id', 'fn_log_read']);

-- 4c. Pharmacist: read-only
GRANT SELECT ON prescriptions, prescription_items, alerts TO onedose_pharmacist;
GRANT SELECT ON v_active_medications, v_pharmacist_patients TO onedose_pharmacist;
SELECT pg_temp.grant_exec('onedose_pharmacist', ARRAY[
    'fn_age_years', 'fn_class_descendants', 'fn_expand_brand', 'fn_search_brands', 'fn_meds_as_of',
    'fn_has_consent', 'fn_log_read']);

-- 4d. Patient: own rows only (policies below)
GRANT SELECT ON patients, patient_allergies, patient_conditions, prescriptions, prescription_items, consents
    TO onedose_patient;
GRANT SELECT ON v_active_medications, v_patient_summary TO onedose_patient;
SELECT pg_temp.grant_exec('onedose_patient', ARRAY['fn_age_years', 'fn_current_patient_id']);

-- 4e. Admin: accounts, cards, devices, audit and statistics. No patient records.
GRANT SELECT (clinician_id, full_name, role, db_username, email, active) ON clinicians TO onedose_admin;
GRANT INSERT, UPDATE ON clinicians TO onedose_admin;
GRANT SELECT, INSERT, UPDATE ON devices TO onedose_admin;
GRANT SELECT (card_id, patient_id, issued_at, active) ON rfid_cards TO onedose_admin;
GRANT INSERT ON rfid_cards TO onedose_admin;
GRANT UPDATE (active) ON rfid_cards TO onedose_admin;
GRANT SELECT (scan_id, device_id, card_id, scanned_at, outcome) ON card_scans TO onedose_admin;
GRANT SELECT ON audit_log, v_audit_recent, mv_alert_stats, consents TO onedose_admin;
GRANT INSERT ON consents TO onedose_admin;
GRANT UPDATE (revoked_at) ON consents TO onedose_admin;
SELECT pg_temp.grant_exec('onedose_admin', ARRAY['fn_refresh_alert_stats', 'fn_verify_audit_chain',
                                                  'fn_audit_payload', 'fn_log_read',
                                                  'fn_alert_severity_counts', 'fn_top_overridden']);

-- 4f. Scanner and API login
SELECT pg_temp.grant_exec('onedose_scanner', ARRAY['fn_record_scan']);
SELECT pg_temp.grant_exec('onedose_api', ARRAY['fn_login']);

-- ---------------------------------------------------------------------
-- 5. Row-level security (consent-driven). Only policies below let rows through.
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' LOOP
        EXECUTE format('DROP POLICY %I ON %I', r.policyname, r.tablename);
    END LOOP;
END $$;

ALTER TABLE patients           ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_allergies  ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE consents           ENABLE ROW LEVEL SECURITY;

-- patients
CREATE POLICY patients_clin_sel ON patients FOR SELECT TO onedose_clinician USING (fn_has_consent(patient_id));
CREATE POLICY patients_pat_sel  ON patients FOR SELECT TO onedose_patient   USING (patient_id = fn_current_patient_id());

-- allergies and conditions
CREATE POLICY allergies_clin_sel ON patient_allergies FOR SELECT TO onedose_clinician USING (fn_has_consent(patient_id));
CREATE POLICY allergies_clin_ins ON patient_allergies FOR INSERT TO onedose_clinician WITH CHECK (fn_has_consent(patient_id));
CREATE POLICY allergies_clin_upd ON patient_allergies FOR UPDATE TO onedose_clinician
    USING (fn_has_consent(patient_id)) WITH CHECK (fn_has_consent(patient_id));
CREATE POLICY allergies_pat_sel  ON patient_allergies FOR SELECT TO onedose_patient USING (patient_id = fn_current_patient_id());

CREATE POLICY conds_clin_sel ON patient_conditions FOR SELECT TO onedose_clinician USING (fn_has_consent(patient_id));
CREATE POLICY conds_clin_ins ON patient_conditions FOR INSERT TO onedose_clinician WITH CHECK (fn_has_consent(patient_id));
CREATE POLICY conds_clin_upd ON patient_conditions FOR UPDATE TO onedose_clinician
    USING (fn_has_consent(patient_id)) WITH CHECK (fn_has_consent(patient_id));
CREATE POLICY conds_pat_sel  ON patient_conditions FOR SELECT TO onedose_patient USING (patient_id = fn_current_patient_id());

-- prescriptions: a clinician can only write prescriptions under their own id
CREATE POLICY rx_clin_sel ON prescriptions FOR SELECT TO onedose_clinician USING (fn_has_consent(patient_id));
CREATE POLICY rx_clin_ins ON prescriptions FOR INSERT TO onedose_clinician
    WITH CHECK (fn_has_consent(patient_id) AND clinician_id = fn_current_clinician_id());
CREATE POLICY rx_pharm_sel ON prescriptions FOR SELECT TO onedose_pharmacist USING (fn_has_consent(patient_id));
CREATE POLICY rx_pat_sel   ON prescriptions FOR SELECT TO onedose_patient    USING (patient_id = fn_current_patient_id());

CREATE POLICY items_clin_sel ON prescription_items FOR SELECT TO onedose_clinician USING (fn_has_consent(patient_id));
CREATE POLICY items_clin_ins ON prescription_items FOR INSERT TO onedose_clinician WITH CHECK (fn_has_consent(patient_id));
CREATE POLICY items_clin_upd ON prescription_items FOR UPDATE TO onedose_clinician
    USING (fn_has_consent(patient_id)) WITH CHECK (fn_has_consent(patient_id));
CREATE POLICY items_pharm_sel ON prescription_items FOR SELECT TO onedose_pharmacist USING (fn_has_consent(patient_id));
CREATE POLICY items_pat_sel   ON prescription_items FOR SELECT TO onedose_patient    USING (patient_id = fn_current_patient_id());

-- alerts: created only by the trigger in 07; clinicians resolve them (as themselves)
CREATE POLICY alerts_clin_sel ON alerts FOR SELECT TO onedose_clinician USING (fn_has_consent(patient_id));
CREATE POLICY alerts_clin_upd ON alerts FOR UPDATE TO onedose_clinician
    USING (fn_has_consent(patient_id))
    WITH CHECK (fn_has_consent(patient_id) AND (resolved_by IS NULL OR resolved_by = fn_current_clinician_id()));
CREATE POLICY alerts_pharm_sel ON alerts FOR SELECT TO onedose_pharmacist USING (fn_has_consent(patient_id));

-- consents: staff record and revoke them (audited by 07); a patient reads their own
CREATE POLICY consents_staff_all ON consents FOR ALL TO onedose_clinician, onedose_admin USING (true) WITH CHECK (true);
CREATE POLICY consents_pat_sel   ON consents FOR SELECT TO onedose_patient USING (patient_id = fn_current_patient_id());

-- =====================================================================
-- End of 08_security.sql
-- =====================================================================
