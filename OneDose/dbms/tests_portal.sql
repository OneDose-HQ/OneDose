-- File: dbms/tests_portal.sql
-- Owner: Bhavya
-- Purpose: Tests for the patient portal (09_patient_portal.sql): patient login, row-level security for the patient role,
--   self-reported medicines and their allergy match, consent grant/revoke, "who viewed my record", symptom search.
-- Inputs: A LOCAL database with 01 to 09 loaded (demo patients 1 to 7, demo clinician dr_demo).
-- Outputs: One NOTICE line per test: PASS, FAIL or SKIP. Everything is rolled back at the end.
-- Depends on: 01 to 09
--
-- Run as a superuser (the tests switch roles with SET ROLE) and NEVER on the hosted database:
--     psql -d onedose -v ON_ERROR_STOP=1 -f dbms/tests_portal.sql
-- This file is separate from tests.sql on purpose, so the original 114 tests are untouched.

\set QUIET on
BEGIN;

CREATE FUNCTION pg_temp.say(p_test text, p_ok boolean, p_detail text DEFAULT '') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '% | % %', CASE WHEN coalesce(p_ok, false) THEN 'PASS' ELSE 'FAIL' END, p_test, p_detail;
END $$;

-- 1. Login
DO $$
DECLARE a integer; b integer;
BEGIN
    SELECT count(*) INTO a FROM fn_patient_login('patient1@onedose.local', 'patient123');
    SELECT count(*) INTO b FROM fn_patient_login('patient1@onedose.local', 'wrong-password');
    PERFORM pg_temp.say('patient login: right password works, wrong password does not', a = 1 AND b = 0);
END $$;

-- 2. The patient role sees only its own rows and no secrets
DO $$
DECLARE own bigint; others bigint; no_logins boolean := false; no_clin boolean := false; no_audit boolean := false;
BEGIN
    PERFORM set_config('onedose.user', 'patient_1', true);
    SET LOCAL ROLE onedose_patient;
    own := fn_current_patient_id();
    SELECT count(*) INTO others FROM prescription_items WHERE patient_id <> 1;
    BEGIN PERFORM 1 FROM patient_logins; EXCEPTION WHEN insufficient_privilege THEN no_logins := true; END;
    BEGIN PERFORM 1 FROM clinicians;     EXCEPTION WHEN insufficient_privilege THEN no_clin := true;   END;
    BEGIN PERFORM 1 FROM audit_log;      EXCEPTION WHEN insufficient_privilege THEN no_audit := true;  END;
    RESET ROLE;
    PERFORM pg_temp.say('patient 1 is identified as patient 1', own = 1);
    PERFORM pg_temp.say('patient 1 sees no prescription items of other patients', others = 0);
    PERFORM pg_temp.say('patient cannot read password hashes, clinicians or the audit log', no_logins AND no_clin AND no_audit);
END $$;

-- 3. Self-reported medicines: own rows only, one target only, only stopped_on can change
DO $$
DECLARE v_brand integer; own_ok boolean := false; other_blocked boolean := false;
        both_blocked boolean := false; upd_blocked boolean := false; stop_ok boolean := false;
BEGIN
    SELECT brand_id INTO v_brand FROM brands ORDER BY brand_id LIMIT 1;
    PERFORM set_config('onedose.user', 'patient_1', true);
    SET LOCAL ROLE onedose_patient;
    INSERT INTO self_reported_meds (patient_id, brand_id, doses_per_day) VALUES (1, v_brand, 2);
    own_ok := true;
    BEGIN INSERT INTO self_reported_meds (patient_id, brand_id, doses_per_day) VALUES (2, v_brand, 1);
    EXCEPTION WHEN insufficient_privilege THEN other_blocked := true; END;
    BEGIN INSERT INTO self_reported_meds (patient_id, brand_id, free_text_name) VALUES (1, v_brand, 'Both given');
    EXCEPTION WHEN check_violation THEN both_blocked := true; END;
    BEGIN UPDATE self_reported_meds SET note = 'changed';
    EXCEPTION WHEN insufficient_privilege THEN upd_blocked := true; END;
    UPDATE self_reported_meds SET stopped_on = current_date WHERE patient_id = 1;
    stop_ok := FOUND;
    RESET ROLE;
    PERFORM pg_temp.say('patient can add a self-reported medicine for themselves', own_ok);
    PERFORM pg_temp.say('patient cannot add one for another patient', other_blocked);
    PERFORM pg_temp.say('a brand and a typed name together are refused', both_blocked);
    PERFORM pg_temp.say('patient can change only stopped_on', upd_blocked AND stop_ok);
END $$;

-- 4. Allergy match: brand pick is checked, typed name says "not checked"
DO $$
DECLARE v_pat bigint; v_brand integer; v_hit boolean; v_free boolean;
BEGIN
    SELECT pa.patient_id, bi.brand_id INTO v_pat, v_brand
    FROM patient_allergies pa JOIN brand_ingredients bi ON bi.ingredient_id = pa.ingredient_id
    WHERE pa.patient_id BETWEEN 1 AND 7 AND pa.ingredient_id IS NOT NULL AND pa.valid_to IS NULL
    ORDER BY pa.patient_id LIMIT 1;
    IF v_pat IS NULL THEN
        RAISE NOTICE 'SKIP | allergy match: no demo patient has an ingredient allergy';
        RETURN;
    END IF;
    INSERT INTO self_reported_meds (patient_id, brand_id, doses_per_day) VALUES (v_pat, v_brand, 1);
    INSERT INTO self_reported_meds (patient_id, free_text_name) VALUES (v_pat, 'Homemade tonic');
    PERFORM set_config('onedose.user', 'patient_' || v_pat, true);
    SET LOCAL ROLE onedose_patient;
    SELECT bool_or(allergy_match) FILTER (WHERE checked), bool_or(NOT checked) INTO v_hit, v_free
    FROM fn_self_reported_rows(v_pat);
    RESET ROLE;
    PERFORM pg_temp.say('allergy match: brand pick is flagged, typed name is marked not checked', v_hit AND v_free);
END $$;

-- 5. Consent: a doctor sees self-reported medicines only while consent is active; the patient can revoke and grant
DO $$
DECLARE with_c integer; without_c integer; revoked boolean; regranted boolean; direct_blocked boolean := false;
BEGIN
    PERFORM set_config('onedose.user', 'dr_demo', true);
    SET LOCAL ROLE onedose_clinician;
    SELECT count(*) INTO with_c FROM fn_self_reported_rows(1);
    BEGIN PERFORM 1 FROM self_reported_meds; EXCEPTION WHEN insufficient_privilege THEN direct_blocked := true; END;
    RESET ROLE;

    PERFORM set_config('onedose.user', 'patient_1', true);
    SET LOCAL ROLE onedose_patient;
    PERFORM fn_portal_revoke_consent();
    RESET ROLE;
    revoked := NOT fn_has_consent(1);

    PERFORM set_config('onedose.user', 'dr_demo', true);
    SET LOCAL ROLE onedose_clinician;
    SELECT count(*) INTO without_c FROM fn_self_reported_rows(1);
    RESET ROLE;

    PERFORM set_config('onedose.user', 'patient_1', true);
    SET LOCAL ROLE onedose_patient;
    PERFORM fn_portal_grant_consent(30);
    RESET ROLE;
    regranted := fn_has_consent(1);

    PERFORM pg_temp.say('clinician sees self-reported medicines while consent is active', with_c >= 1);
    PERFORM pg_temp.say('clinician cannot read the table directly', direct_blocked);
    PERFORM pg_temp.say('patient revoke removes access at once', revoked AND without_c = 0);
    PERFORM pg_temp.say('patient grant restores access', regranted);
END $$;

-- 6. Who viewed my record
DO $$
DECLARE seen boolean; blocked boolean := false;
BEGIN
    PERFORM set_config('onedose.user', 'dr_demo', true);
    PERFORM fn_log_read('patients', '1');
    PERFORM set_config('onedose.user', 'patient_1', true);
    SET LOCAL ROLE onedose_patient;
    SELECT bool_or(who = 'Dr. Demo Clinician') INTO seen FROM fn_portal_access_log(20);
    RESET ROLE;
    PERFORM set_config('onedose.user', 'dr_demo', true);
    SET LOCAL ROLE onedose_clinician;
    BEGIN PERFORM * FROM fn_portal_access_log(5); EXCEPTION WHEN insufficient_privilege THEN blocked := true; END;
    RESET ROLE;
    PERFORM pg_temp.say('access log shows the doctor who opened the record', seen);
    PERFORM pg_temp.say('a clinician cannot call the patient access-log function', blocked);
END $$;

-- 7. Symptom search
DO $$
DECLARE v_pat bigint; n integer;
BEGIN
    SELECT pi.patient_id INTO v_pat
    FROM prescription_items pi
    JOIN brand_ingredients bi ON bi.brand_id = pi.brand_id
    JOIN ingredient_indications ii ON ii.ingredient_id = bi.ingredient_id
    JOIN indications ind ON ind.indication_id = ii.indication_id
    WHERE pi.patient_id BETWEEN 1 AND 7 AND ind.name = 'fever'
    ORDER BY pi.patient_id LIMIT 1;
    IF v_pat IS NULL THEN
        RAISE NOTICE 'SKIP | symptom search: no demo patient has a fever medicine';
        RETURN;
    END IF;
    PERFORM set_config('onedose.user', 'patient_' || v_pat, true);
    SET LOCAL ROLE onedose_patient;
    SELECT count(*) INTO n FROM fn_portal_symptom_search('fever');
    RESET ROLE;
    PERFORM pg_temp.say('symptom search finds the fever medicine with prescriber', n >= 1, 'rows=' || n);
END $$;

ROLLBACK;
