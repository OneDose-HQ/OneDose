-- File: dbms/tests.sql
-- Owner: Bhavya  (only the owner edits this file)
-- Purpose: Prove every part of the database works: data quality, lookups, the five checks, safer alternatives,
--   triggers, audit chain, roles and consent (row-level security), card scans, views, constraints, and the
--   concurrency race (write skew). One PASS / FAIL / WARN / SKIP line per test, then a summary.
-- Inputs: A database with 01 to 08 loaded (demo patients 1 to 7 and the demo clinicians come from 02 and 06).
-- Outputs: The report. The exit code is non-zero when any test FAILs (run with -v ON_ERROR_STOP=1).
-- Depends on: 01_schema.sql ... 08_security.sql
--
-- How to run (as a superuser such as postgres: the tests switch roles with SET ROLE):
--     psql -d onedose -v ON_ERROR_STOP=1 -f dbms/tests.sql
-- The race test (section I) opens two extra connections with the dblink extension. If the default does not
-- connect (password login, remote host), pass a connection string:
--     psql -d onedose -v ON_ERROR_STOP=1 -v race_conn="dbname=onedose host=localhost user=postgres password=..." -f dbms/tests.sql
-- Sections A to H run inside ONE transaction that is rolled back, so they leave nothing behind.
-- Section I must commit (two sessions need to see the data): it leaves two 'RACE-TEST' patients with their
-- items, alerts and audit rows, because alerts and the audit log can never be deleted by design.
-- Status meaning: PASS ok | FAIL bug (fix it) | WARN data or review gap, not a bug | SKIP could not run here.

\set QUIET on
\pset null '-'
\if :{?race_conn}
\else
  \set race_conn ''
\endif

-- ---------------------------------------------------------------------
-- Test helpers (session-level temp objects; they disappear when psql ends)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_res (n serial, section text, test text, status text, detail text);
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text);

CREATE FUNCTION pg_temp.setctx(p_k text, p_v text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO pg_temp.t_ctx VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v $$;
CREATE FUNCTION pg_temp.ctx(p_k text) RETURNS text LANGUAGE sql AS
$$ SELECT v FROM pg_temp.t_ctx WHERE k = p_k $$;
CREATE FUNCTION pg_temp.brand(p_name text) RETURNS integer LANGUAGE sql AS
$$ SELECT brand_id FROM brands WHERE brand_name = p_name $$;
CREATE FUNCTION pg_temp.ing(p_name text) RETURNS integer LANGUAGE sql AS
$$ SELECT ingredient_id FROM ingredients WHERE name = p_name $$;

-- record one result
CREATE FUNCTION pg_temp.expect(p_section text, p_test text, p_ok boolean, p_detail text DEFAULT '',
                               p_level text DEFAULT 'FAIL') RETURNS void LANGUAGE sql AS
$$ INSERT INTO pg_temp.t_res (section, test, status, detail)
   VALUES (p_section, p_test,
           CASE WHEN p_detail LIKE 'SKIP:%' THEN 'SKIP' WHEN coalesce(p_ok, false) THEN 'PASS' ELSE p_level END,
           p_detail) $$;

-- run a query that returns (ok boolean, detail text); an error counts as a failure
CREATE FUNCTION pg_temp.t(p_section text, p_test text, p_sql text, p_level text DEFAULT 'FAIL') RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean; v_detail text;
BEGIN
    BEGIN
        EXECUTE p_sql INTO v_ok, v_detail;
    EXCEPTION WHEN OTHERS THEN
        v_ok := false; v_detail := 'error ' || SQLSTATE || ': ' || SQLERRM;
    END;
    PERFORM pg_temp.expect(p_section, p_test, v_ok, coalesce(v_detail, ''), p_level);
END $$;

-- run a statement and return its SQLSTATE ('none' when it worked). A failed statement is rolled back.
CREATE FUNCTION pg_temp.err_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN 'none';
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE;
END $$;

-- expect a statement to fail with a given SQLSTATE
CREATE FUNCTION pg_temp.te(p_section text, p_test text, p_sql text, p_expected text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v text := pg_temp.err_of(p_sql);
BEGIN
    PERFORM pg_temp.expect(p_section, p_test, v = p_expected, 'SQLSTATE ' || v || ' (expected ' || p_expected || ')');
END $$;

-- run one statement as a database role + app user. Returns 'OK:<first value>' or 'ERR:<sqlstate>'.
-- The statement must return a row (SELECT ... or DML ... RETURNING).
CREATE FUNCTION pg_temp.as_role(p_role text, p_user text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_role);
        PERFORM set_config('onedose.user', coalesce(p_user, ''), true);
        EXECUTE p_sql INTO v;
        RESET ROLE;
        PERFORM set_config('onedose.user', '', true);
        RETURN 'OK:' || coalesce(v, 'null');
    EXCEPTION WHEN OTHERS THEN
        RETURN 'ERR:' || SQLSTATE;
    END;
END $$;

-- same, then compare with an expected value (LIKE pattern)
CREATE FUNCTION pg_temp.tr(p_section text, p_test text, p_role text, p_user text, p_sql text, p_expect text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_temp.as_role(p_role, p_user, p_sql);
BEGIN
    PERFORM pg_temp.expect(p_section, p_test, v LIKE p_expect, 'got ' || v || ' (expected ' || p_expect || ')');
END $$;

-- tamper with an audit row inside a sub-transaction, ask the verifier, then undo everything
CREATE FUNCTION pg_temp.tamper_test() RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_valid boolean; v_bad bigint;
BEGIN
    SELECT min(audit_id) INTO v_id FROM audit_log;
    ALTER TABLE audit_log DISABLE TRIGGER trg_audit_log_block_change;
    UPDATE audit_log SET actor = 'mallory' WHERE audit_id = v_id;
    SELECT is_valid, first_bad_audit_id INTO v_valid, v_bad FROM fn_verify_audit_chain();
    RAISE EXCEPTION 'undo|%|%|%', v_valid, v_bad, v_id;
EXCEPTION WHEN raise_exception THEN
    RETURN SQLERRM;
END $$;

-- =====================================================================
BEGIN;
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Data quality (the curated drug data)
-- ---------------------------------------------------------------------
DO $do$
BEGIN
    PERFORM pg_temp.t('A', 'every brand has at least one ingredient',
      $q$ SELECT count(*) = 0, string_agg(brand_name, ', ')
          FROM brands b WHERE NOT EXISTS (SELECT 1 FROM brand_ingredients bi WHERE bi.brand_id = b.brand_id) $q$);
    PERFORM pg_temp.t('A', 'single-ingredient brand: label strength equals stored mg',
      $q$ SELECT count(*) = 0,
                 string_agg(b.brand_name || ' (label ' || b.strength || ', stored ' || bi.strength_mg || ' mg)', '; ')
          FROM brands b JOIN brand_ingredients bi ON bi.brand_id = b.brand_id
          WHERE b.strength ~ '^[0-9.]+ ?mg$'
            AND (SELECT count(*) FROM brand_ingredients x WHERE x.brand_id = b.brand_id) = 1
            AND regexp_replace(b.strength, '[^0-9.]', '', 'g')::numeric <> bi.strength_mg $q$);
    PERFORM pg_temp.t('A', 'all 7 demo patients have an active card and a valid consent',
      $q$ SELECT count(*) = 7, count(*)::text || ' of 7'
          FROM patients p WHERE p.patient_id BETWEEN 1 AND 7 AND fn_has_consent(p.patient_id)
            AND EXISTS (SELECT 1 FROM rfid_cards c WHERE c.patient_id = p.patient_id AND c.active) $q$);
    PERFORM pg_temp.t('A', 'dose limits exist for children (under 18)',
      $q$ SELECT EXISTS (SELECT 1 FROM dose_limits WHERE age_min_years < 18),
                 (SELECT count(*) FROM patients WHERE fn_age_years(date_of_birth) < 18)::text
                 || ' patients are under 18 and get no dose check' $q$, 'WARN');
    PERFORM pg_temp.t('A', 'every source was reviewed by a pharmacist or doctor',
      $q$ SELECT count(*) = 0, count(*)::text || ' sources have no reviewed_by' FROM sources WHERE reviewed_by IS NULL $q$, 'WARN');
END $do$;

-- ---------------------------------------------------------------------
-- B. Lookups (03)
-- ---------------------------------------------------------------------
DO $do$
BEGIN
    PERFORM pg_temp.t('B', 'fn_expand_brand splits a combination tablet (Combiflam)',
      $q$ SELECT count(*) = 2 AND bool_or(ingredient_name = 'ibuprofen' AND strength_mg = 400)
                 AND bool_or(ingredient_name = 'paracetamol' AND strength_mg = 325),
                 string_agg(ingredient_name || ' ' || strength_mg, ', ')
          FROM fn_expand_brand(pg_temp.brand('Combiflam')) $q$);
    PERFORM pg_temp.t('B', 'fn_search_brands finds "Dolo 650" from the typo "dollo 650"',
      $q$ SELECT (array_agg(brand_name ORDER BY match_score DESC))[1] = 'Dolo 650',
                 string_agg(brand_name, ', ') FROM fn_search_brands('dollo 650', 3) $q$);
    PERFORM pg_temp.t('B', 'fn_class_descendants includes the class itself',
      $q$ SELECT count(*) FILTER (WHERE class_id = 23) = 1, count(*)::text || ' classes'
          FROM fn_class_descendants(23) $q$);
    PERFORM pg_temp.t('B', 'class tree: amoxicillin is under Antibiotic (via Penicillin), paracetamol is not',
      $q$ SELECT fn_in_class_tree(pg_temp.ing('amoxicillin'), (SELECT class_id FROM drug_classes WHERE name = 'Antibiotic'))
                 AND NOT fn_in_class_tree(pg_temp.ing('paracetamol'), (SELECT class_id FROM drug_classes WHERE name = 'Antibiotic')),
                 'checked amoxicillin and paracetamol' $q$);
    PERFORM pg_temp.t('B', 'fn_meds_as_of: warfarin today, nothing 20 years ago (time travel)',
      $q$ SELECT EXISTS (SELECT 1 FROM fn_meds_as_of(1, current_date) WHERE brand_name = 'Warf 5')
                 AND NOT EXISTS (SELECT 1 FROM fn_meds_as_of(1, current_date - 7300)),
                 'patient 1' $q$);
END $do$;

-- ---------------------------------------------------------------------
-- C. The five checks (04) on the demo patients
--    1 Demo A: warfarin, penicillin allergy      2 Demo B: Dolo 650        3 Demo C: kidney disease, Losar
--    6 Demo F: no medicines (clean)               7 Demo G: pregnant
-- ---------------------------------------------------------------------
DO $do$
DECLARE v_rx bigint;
BEGIN
    -- clean case FIRST: patient 6 has nothing yet
    PERFORM pg_temp.t('C', 'clean prescription: Demo F + Dolo 650 gives no alerts',
      $q$ SELECT count(*) = 0, count(*)::text || ' alerts' FROM fn_check_prescription(6, pg_temp.brand('Dolo 650'), 1, 3) $q$);

    -- 1 duplicate therapy
    PERFORM pg_temp.t('C', '1 duplicate: Dolo 650 active + Combiflam (paracetamol inside a combination)',
      $q$ SELECT count(*) = 1 AND bool_and(ingredient_name = 'paracetamol' AND severity = 'major'),
                 string_agg(detail, '|') FROM chk_duplicate(2, pg_temp.brand('Combiflam')) $q$);
    PERFORM pg_temp.t('C', '1 duplicate: the same brand twice is flagged',
      $q$ SELECT count(*) = 1, count(*)::text FROM chk_duplicate(2, pg_temp.brand('Dolo 650')) $q$);

    -- 2 interaction
    PERFORM pg_temp.t('C', '2 interaction: warfarin active + Brufen (ibuprofen) is major or worse',
      $q$ SELECT count(*) >= 1 AND bool_or(ingredient_name = 'ibuprofen' AND related_ingredient_name = 'warfarin' AND severity >= 'major'),
                 string_agg(severity::text, ',') FROM chk_interaction(1, pg_temp.brand('Brufen 400')) $q$);
    PERFORM pg_temp.t('C', '2 interaction: a pair has one alert only (direct and class-level rows are merged)',
      $q$ SELECT count(*) = count(DISTINCT (ingredient_id, related_ingredient_id)), count(*)::text
          FROM chk_interaction(1, pg_temp.brand('Brufen 400')) $q$);

    -- 3 allergy
    PERFORM pg_temp.t('C', '3 allergy: penicillin-class allergy catches both ingredients of Augmentin',
      $q$ SELECT count(*) = 2 AND bool_and(severity = 'critical'), string_agg(ingredient_name, ' + ')
          FROM chk_allergy(1, pg_temp.brand('Augmentin 625')) $q$);
    PERFORM pg_temp.t('C', '3 allergy: no false alarm for Dolo 650',
      $q$ SELECT count(*) = 0, count(*)::text FROM chk_allergy(1, pg_temp.brand('Dolo 650')) $q$);

    -- 4 contraindication
    PERFORM pg_temp.t('C', '4 contraindication: kidney disease + Brufen',
      $q$ SELECT count(*) >= 1 AND bool_or(ingredient_name = 'ibuprofen' AND detail ILIKE '%kidney%'),
                 string_agg(detail, '|') FROM chk_contraindication(3, pg_temp.brand('Brufen 400')) $q$);
    PERFORM pg_temp.t('C', '4 contraindication: pregnancy + warfarin is critical',
      $q$ SELECT count(*) = 1 AND bool_and(severity = 'critical'), string_agg(detail, '|')
          FROM chk_contraindication(7, pg_temp.brand('Warf 5')) $q$);

    -- 5 daily dose
    PERFORM pg_temp.t('C', '5 dose: Dolo 650 (1950 mg) + Crocin 2 x 4 (4000 mg) = 5950 mg, over the 4000 mg limit',
      $q$ SELECT count(*) = 1 AND bool_and(severity >= 'major') AND bool_and(detail LIKE '5950%'), string_agg(detail, '|')
          FROM chk_dose(2, pg_temp.brand('Crocin Advance'), 2, 4) $q$);
    PERFORM pg_temp.t('C', '5 dose: a small extra dose stays under the limit',
      $q$ SELECT count(*) = 0, count(*)::text FROM chk_dose(2, pg_temp.brand('Crocin Advance'), 1, 1) $q$);

    -- ranking
    PERFORM pg_temp.t('C', 'fn_check_prescription ranks alerts by severity (critical first, no inversion)',
      $q$ WITH r AS (SELECT * FROM fn_check_prescription(3, pg_temp.brand('Brufen 400'), 1, 3))
          SELECT (SELECT count(*) FROM r) >= 2
                 AND NOT EXISTS (SELECT 1 FROM r a JOIN r b ON a.alert_rank < b.alert_rank AND a.severity < b.severity)
                 AND (SELECT count(*) = max(alert_rank) FROM r),
                 (SELECT string_agg(alert_rank || ':' || severity || ':' || check_type, ', ' ORDER BY alert_rank) FROM r) $q$);

    -- time-aware allergy: an expired allergy is ignored, a current one counts (Demo F, fixtures)
    INSERT INTO patient_allergies (patient_id, ingredient_id, reaction, valid_from, valid_to)
    VALUES (6, pg_temp.ing('paracetamol'), 'old rash', current_date - 700, current_date - 1);
    PERFORM pg_temp.t('C', '3 allergy: an allergy that ended yesterday is ignored',
      $q$ SELECT count(*) = 0, count(*)::text FROM chk_allergy(6, pg_temp.brand('Dolo 650')) $q$);
    INSERT INTO patient_allergies (patient_id, ingredient_id, reaction, valid_from)
    VALUES (6, pg_temp.ing('paracetamol'), 'hives', current_date - 10);
    PERFORM pg_temp.t('C', '3 allergy: a current allergy to the exact ingredient is critical',
      $q$ SELECT count(*) = 1 AND bool_and(severity = 'critical'), count(*)::text FROM chk_allergy(6, pg_temp.brand('Dolo 650')) $q$);
    INSERT INTO patient_allergies (patient_id, class_id, reaction, valid_from)
    VALUES (6, (SELECT class_id FROM drug_classes WHERE name = 'Antibiotic'), 'swelling', current_date - 10);
    PERFORM pg_temp.t('C', '3 allergy: an allergy to the PARENT class (Antibiotic) catches Augmentin through the tree',
      $q$ SELECT count(*) = 2 AND bool_and(severity >= 'major'), string_agg(ingredient_name, ' + ')
          FROM chk_allergy(6, pg_temp.brand('Augmentin 625')) $q$);

    -- time-aware medicines: an ended medicine is ignored today but counted inside its period (Demo G)
    INSERT INTO prescriptions (patient_id, clinician_id) VALUES (7, 1) RETURNING prescription_id INTO v_rx;
    INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day, start_date, end_date)
    VALUES (v_rx, 7, pg_temp.brand('Warf 5'), 1, 1, current_date - 90, current_date - 30);
    PERFORM pg_temp.t('C', '2 interaction: a medicine that ended 30 days ago is not active today',
      $q$ SELECT count(*) = 0, count(*)::text FROM chk_interaction(7, pg_temp.brand('Brufen 400')) $q$);
    PERFORM pg_temp.t('C', '2 interaction: the same medicine counts when checking a date inside its period',
      $q$ SELECT count(*) >= 1, count(*)::text FROM chk_interaction(7, pg_temp.brand('Brufen 400'), current_date - 60) $q$);

    -- the pair table is stored once; the check works whichever side is "new": Brufen active on Demo F, new = warfarin
    INSERT INTO prescriptions (patient_id, clinician_id) VALUES (6, 1) RETURNING prescription_id INTO v_rx;
    INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day)
    VALUES (v_rx, 6, pg_temp.brand('Brufen 400'), 1, 3);
    PERFORM pg_temp.t('C', '2 interaction: works from either side of the stored pair (ibuprofen active, warfarin new)',
      $q$ SELECT count(*) >= 1 AND bool_or(ingredient_name = 'warfarin' AND related_ingredient_name = 'ibuprofen'),
                 string_agg(severity::text, ',') FROM chk_interaction(6, pg_temp.brand('Warf 5')) $q$);
END $do$;

-- ---------------------------------------------------------------------
-- D. Safer alternatives (04)
-- ---------------------------------------------------------------------
DO $do$
BEGIN
    PERFORM pg_temp.t('D', 'Demo A (warfarin) wants Brufen: alternatives exist, never the same brand, never Combiflam',
      $q$ SELECT count(*) >= 1 AND NOT bool_or(brand_name IN ('Brufen 400', 'Combiflam')),
                 string_agg(brand_name, ', ' ORDER BY alt_rank) FROM fn_safe_alternatives(1, pg_temp.brand('Brufen 400')) $q$);
    PERFORM pg_temp.t('D', 'no alternative has a moderate-or-worse conflict with this patient (Brufen request)',
      $q$ SELECT count(*) = 0, string_agg(a.brand_name || ':' || k.check_type, ', ')
          FROM fn_safe_alternatives(1, pg_temp.brand('Brufen 400')) a,
               LATERAL fn_check_core(1, a.brand_id) k WHERE k.severity >= 'moderate' $q$);
    PERFORM pg_temp.t('D', 'no alternative breaks the penicillin allergy (Augmentin request)',
      $q$ SELECT count(*) = 0, string_agg(a.brand_name || ':' || k.check_type, ', ')
          FROM fn_safe_alternatives(1, pg_temp.brand('Augmentin 625')) a,
               LATERAL fn_check_core(1, a.brand_id) k WHERE k.severity >= 'moderate' $q$);
    PERFORM pg_temp.t('D', 'alternatives are ranked: lower line of therapy first, then fewer minor interactions',
      $q$ WITH a AS (SELECT * FROM fn_safe_alternatives(1, pg_temp.brand('Brufen 400')))
          SELECT NOT EXISTS (SELECT 1 FROM a x JOIN a y ON x.alt_rank < y.alt_rank
                             AND (x.line_of_therapy, x.minor_count) > (y.line_of_therapy, y.minor_count)),
                 (SELECT string_agg(brand_name || '(L' || line_of_therapy || ',minor=' || minor_count || ')', ' > ' ORDER BY alt_rank) FROM a) $q$);
    PERFORM pg_temp.t('D', 'the alternatives list respects p_limit',
      $q$ SELECT count(*) <= 2, count(*)::text FROM fn_safe_alternatives(1, pg_temp.brand('Brufen 400'), current_date, 2) $q$);
END $do$;

-- ---------------------------------------------------------------------
-- E. Triggers and the audit chain (07), as the table owner
-- ---------------------------------------------------------------------
DO $do$
DECLARE
    v_exp text; v_act text; v_rx bigint; v_item bigint; v_a1 bigint;
    v_rx3 bigint; v_item3 bigint; v_a3 bigint; v_n_before bigint; v_n integer;
    v_t text;
BEGIN
    -- prescribe Brufen to Demo A (warfarin): the alerts the check predicts must be the alerts the trigger writes
    SELECT string_agg(r.check_type::text || ':' || r.ingredient_id || ':' || coalesce(r.related_ingredient_id, 0), ',' ORDER BY r.check_type::text, r.ingredient_id, r.related_ingredient_id)
      INTO v_exp FROM fn_check_prescription(1, pg_temp.brand('Brufen 400'), 1, 3) r;
    INSERT INTO prescriptions (patient_id, clinician_id) VALUES (1, 1) RETURNING prescription_id INTO v_rx;
    INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day)
    VALUES (v_rx, 1, pg_temp.brand('Brufen 400'), 1, 3) RETURNING item_id INTO v_item;
    SELECT string_agg(a.check_type::text || ':' || a.ingredient_id || ':' || coalesce(a.related_ingredient_id, 0), ',' ORDER BY a.check_type::text, a.ingredient_id, a.related_ingredient_id)
      INTO v_act FROM alerts a WHERE a.item_id = v_item;
    PERFORM pg_temp.expect('E', 'inserting an item writes exactly the alerts the check predicted',
        v_exp IS NOT NULL AND v_exp = v_act, 'predicted ' || coalesce(v_exp, 'none') || ' / written ' || coalesce(v_act, 'none'));
    PERFORM pg_temp.t('E', 'the new item is not flagged as a duplicate of itself',
        format($q$ SELECT count(*) = 0, count(*)::text FROM alerts WHERE item_id = %s AND check_type = 'duplicate' $q$, v_item));
    PERFORM pg_temp.t('E', 'alerts are linked to the item and the clinician and start OPEN',
        format($q$ SELECT count(*) >= 1 AND bool_and(clinician_id = 1 AND status = 'open' AND patient_id = 1 AND resolved_at IS NULL), count(*)::text
                  FROM alerts WHERE item_id = %s $q$, v_item));
    PERFORM pg_temp.setctx('rx1', v_rx::text);

    -- a second prescription with two alerts (Demo C: kidney disease + Brufen)
    INSERT INTO prescriptions (patient_id, clinician_id) VALUES (3, 1) RETURNING prescription_id INTO v_rx3;
    INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day)
    VALUES (v_rx3, 3, pg_temp.brand('Brufen 400'), 1, 3) RETURNING item_id INTO v_item3;
    SELECT min(alert_id) INTO v_a3 FROM alerts WHERE item_id = v_item3;
    SELECT min(alert_id) INTO v_a1 FROM alerts WHERE item_id = v_item;

    -- override rules
    PERFORM pg_temp.te('E', 'overriding an alert WITHOUT a reason is refused',
        format($q$ UPDATE alerts SET status = 'overridden', resolved_by = 1 WHERE alert_id = %s $q$, v_a1), '23514');
    PERFORM pg_temp.te('E', 'a blank reason is refused too',
        format($q$ UPDATE alerts SET status = 'overridden', override_reason = '   ' WHERE alert_id = %s $q$, v_a1), '23514');
    PERFORM pg_temp.te('E', 'the core facts of an open alert cannot be edited (severity)',
        format($q$ UPDATE alerts SET severity = 'minor' WHERE alert_id = %s $q$, v_a3), '42501');
    PERFORM pg_temp.te('E', 'an explanation can be added to an open alert',
        format($q$ UPDATE alerts SET explanation = 'Two plain sentences.' WHERE alert_id = %s $q$, v_a3), 'none');
    PERFORM pg_temp.te('E', 'overriding WITH a reason works',
        format($q$ UPDATE alerts SET status = 'overridden', override_reason = 'Benefit outweighs the risk, INR monitored', resolved_by = 1 WHERE alert_id = %s $q$, v_a1), 'none');
    PERFORM pg_temp.t('E', 'resolving an alert stamps resolved_at',
        format($q$ SELECT resolved_at IS NOT NULL AND status = 'overridden', status::text FROM alerts WHERE alert_id = %s $q$, v_a1));
    PERFORM pg_temp.te('E', 'a resolved alert can never change again',
        format($q$ UPDATE alerts SET status = 'accepted' WHERE alert_id = %s $q$, v_a1), '42501');
    PERFORM pg_temp.te('E', 'alerts cannot be deleted', 'DELETE FROM alerts', '42501');
    SET CONSTRAINTS ALL IMMEDIATE;   -- settle the deferred alert -> item checks, or TRUNCATE is refused for another reason
    PERFORM pg_temp.te('E', 'alerts cannot be truncated', 'TRUNCATE alerts', '42501');
    SET CONSTRAINTS ALL DEFERRED;    -- back to normal: 07 writes alerts before the item row exists

    -- audit log
    PERFORM pg_temp.t('E', 'the item insert was audited (INSERT row for prescription_items)',
        format($q$ SELECT count(*) = 1, count(*)::text FROM audit_log
                  WHERE table_name = 'prescription_items' AND action = 'INSERT' AND row_pk = '%s' $q$, v_item));
    PERFORM pg_temp.t('E', 'the alert resolution was audited (UPDATE row for alerts)',
        format($q$ SELECT count(*) >= 1, count(*)::text FROM audit_log
                  WHERE table_name = 'alerts' AND action = 'UPDATE' AND row_pk = '%s' $q$, v_a1));
    PERFORM set_config('onedose.user', 'dr_demo', true);
    PERFORM fn_log_read('patients', '1');
    PERFORM set_config('onedose.user', '', true);
    PERFORM pg_temp.t('E', 'fn_log_read records a READ with the real user as actor',
        $q$ SELECT count(*) >= 1, count(*)::text FROM audit_log WHERE action = 'READ' AND table_name = 'patients' AND actor = 'dr_demo' $q$);
    PERFORM pg_temp.t('E', 'the audit hash chain verifies',
        $q$ SELECT is_valid AND rows_checked > 5, rows_checked || ' rows checked' FROM fn_verify_audit_chain() $q$);
    PERFORM pg_temp.te('E', 'audit_log cannot be updated', 'UPDATE audit_log SET actor = ''x''', '42501');
    PERFORM pg_temp.te('E', 'audit_log cannot be deleted', 'DELETE FROM audit_log', '42501');
    PERFORM pg_temp.te('E', 'audit_log cannot be truncated', 'TRUNCATE audit_log', '42501');
    v_t := pg_temp.tamper_test();
    PERFORM pg_temp.expect('E', 'tampering with an audit row is detected by fn_verify_audit_chain',
        split_part(v_t, '|', 2) = 'f' AND split_part(v_t, '|', 3) = split_part(v_t, '|', 4), v_t);
    PERFORM pg_temp.t('E', 'the tamper test was fully undone (chain valid again)',
        $q$ SELECT is_valid, rows_checked::text FROM fn_verify_audit_chain() $q$);

    -- exclusion constraint: same brand, overlapping dates
    PERFORM pg_temp.te('E', 'the same brand cannot overlap itself for one patient (exclusion constraint)',
        format($q$ INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day)
                  VALUES (%s, 1, %s, 1, 1) $q$, v_rx, pg_temp.brand('Warf 5')), '23P01');
END $do$;

-- ---------------------------------------------------------------------
-- F. Security (08): roles, consent, card scans
-- ---------------------------------------------------------------------
DO $do$
DECLARE
    v text; v_rx bigint; v_item bigint; v_alert bigint; v_n_before bigint; v_dev integer;
    v_o text; v_p bigint;
BEGIN
    -- login
    PERFORM pg_temp.t('F', 'fn_login: right password returns the clinician',
        $q$ SELECT count(*) = 1 AND min(role::text) = 'clinician', count(*)::text FROM fn_login('dr_demo', 'clinician123') $q$);
    PERFORM pg_temp.t('F', 'fn_login: wrong password and unknown user return nothing',
        $q$ SELECT (SELECT count(*) FROM fn_login('dr_demo', 'wrong')) = 0 AND (SELECT count(*) FROM fn_login('nobody', 'x')) = 0, 'no rows' $q$);

    -- consent state used by the policies
    UPDATE consents SET granted_at = now() - interval '60 days', expires_at = now() - interval '1 day' WHERE patient_id = 4;
    UPDATE consents SET revoked_at = now() WHERE patient_id = 5;
    PERFORM pg_temp.t('F', 'fn_has_consent: valid yes; expired no; revoked no; never given no',
        $q$ SELECT fn_has_consent(1) AND NOT fn_has_consent(4) AND NOT fn_has_consent(5) AND NOT fn_has_consent(1001), 'checked 1, 4, 5, 1001' $q$);
    INSERT INTO consents (patient_id, expires_at) VALUES (5, now() + interval '1 year');
    PERFORM pg_temp.t('F', 'fn_has_consent: a newer consent replaces a revoked one',
        $q$ SELECT fn_has_consent(5), 'patient 5' $q$);
    UPDATE consents SET revoked_at = now() WHERE patient_id = 5;

    -- clinician
    PERFORM pg_temp.tr('F', 'clinician sees a patient who gave consent', 'onedose_clinician', 'dr_demo',
        'SELECT count(*) FROM patients WHERE patient_id = 1', 'OK:1');
    PERFORM pg_temp.tr('F', 'clinician does NOT see a patient without consent', 'onedose_clinician', 'dr_demo',
        'SELECT count(*) FROM patients WHERE patient_id = 1001', 'OK:0');
    PERFORM pg_temp.tr('F', 'clinician does not see patients whose consent expired or was revoked', 'onedose_clinician', 'dr_demo',
        'SELECT count(*) FROM patients WHERE patient_id IN (4, 5)', 'OK:0');
    PERFORM pg_temp.tr('F', 'clinician gets no alerts for a patient without consent (API must check consent first)', 'onedose_clinician', 'dr_demo',
        format('SELECT count(*) FROM fn_check_prescription(1001, %s, 1, 1)', pg_temp.brand('Brufen 400')), 'OK:0');
    PERFORM pg_temp.tr('F', 'clinician cannot insert alerts directly', 'onedose_clinician', 'dr_demo',
        format('INSERT INTO alerts (patient_id, brand_id, check_type, severity) VALUES (1, %s, ''duplicate'', ''minor'') RETURNING alert_id', pg_temp.brand('Dolo 650')), 'ERR:42501');
    PERFORM pg_temp.tr('F', 'clinician cannot read the audit log', 'onedose_clinician', 'dr_demo',
        'SELECT count(*) FROM audit_log', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'clinician cannot read password hashes', 'onedose_clinician', 'dr_demo',
        'SELECT password_hash FROM clinicians LIMIT 1', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'clinician cannot prescribe under another clinician''s name', 'onedose_clinician', 'dr_demo',
        'INSERT INTO prescriptions (patient_id, clinician_id) VALUES (2, 2) RETURNING prescription_id', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'clinician cannot prescribe to a patient without consent', 'onedose_clinician', 'dr_demo',
        'INSERT INTO prescriptions (patient_id, clinician_id) VALUES (1001, 1) RETURNING prescription_id', 'ERR:42501');

    -- clinician prescribes end to end (the alert trigger runs with definer rights)
    v := pg_temp.as_role('onedose_clinician', 'dr_demo',
        'INSERT INTO prescriptions (patient_id, clinician_id) VALUES (2, 1) RETURNING prescription_id');
    PERFORM pg_temp.expect('F', 'clinician can create a prescription for a consented patient as themselves', v LIKE 'OK:%', v);
    v_rx := nullif(substring(v from 4), 'null')::bigint;
    v := pg_temp.as_role('onedose_clinician', 'dr_demo', format(
        'INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day) VALUES (%s, 2, %s, 1, 3) RETURNING item_id',
        v_rx, pg_temp.brand('Combiflam')));
    PERFORM pg_temp.expect('F', 'clinician can add the item (Combiflam on top of Dolo 650)', v LIKE 'OK:%', v);
    v_item := nullif(substring(v from 4), 'null')::bigint;
    PERFORM pg_temp.t('F', 'the alert trigger still wrote the duplicate alert although the clinician cannot insert alerts',
        format($q$ SELECT count(*) = 1 AND bool_and(check_type = 'duplicate' AND status = 'open'), count(*)::text FROM alerts WHERE item_id = %s $q$, v_item));
    SELECT alert_id INTO v_alert FROM alerts WHERE item_id = v_item LIMIT 1;
    PERFORM pg_temp.tr('F', 'clinician cannot rewrite an alert (severity)', 'onedose_clinician', 'dr_demo',
        format('UPDATE alerts SET severity = ''minor'' WHERE alert_id = %s RETURNING alert_id', v_alert), 'ERR:42501');
    PERFORM pg_temp.tr('F', 'clinician cannot resolve an alert in another clinician''s name', 'onedose_clinician', 'dr_demo',
        format('UPDATE alerts SET status = ''accepted'', resolved_by = 2 WHERE alert_id = %s RETURNING alert_id', v_alert), 'ERR:42501');
    PERFORM pg_temp.tr('F', 'clinician resolves an alert as themselves', 'onedose_clinician', 'dr_demo',
        format('UPDATE alerts SET status = ''accepted'', resolved_by = 1 WHERE alert_id = %s RETURNING alert_id', v_alert), 'OK:' || v_alert);

    -- pharmacist
    PERFORM pg_temp.tr('F', 'pharmacist cannot read the patients table', 'onedose_pharmacist', 'pharm_demo',
        'SELECT count(*) FROM patients', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'pharmacist sees a consented patient through the masked view', 'onedose_pharmacist', 'pharm_demo',
        'SELECT count(*) FROM v_pharmacist_patients WHERE patient_id = 1', 'OK:1');
    PERFORM pg_temp.tr('F', 'pharmacist does not see patients without consent', 'onedose_pharmacist', 'pharm_demo',
        'SELECT count(*) FROM v_pharmacist_patients WHERE patient_id IN (4, 5, 1001)', 'OK:0');
    PERFORM pg_temp.tr('F', 'the masked name shows initials only', 'onedose_pharmacist', 'pharm_demo',
        'SELECT masked_name FROM v_pharmacist_patients WHERE patient_id = 1', 'OK:D. P. A.');
    PERFORM pg_temp.t('F', 'the pharmacist view has no name, date of birth, weight or sex column',
        $q$ SELECT count(*) = 0, string_agg(column_name, ', ') FROM information_schema.columns
            WHERE table_name = 'v_pharmacist_patients' AND column_name IN ('full_name', 'date_of_birth', 'weight_kg', 'sex') $q$);
    PERFORM pg_temp.tr('F', 'pharmacist cannot prescribe', 'onedose_pharmacist', 'pharm_demo',
        'INSERT INTO prescriptions (patient_id, clinician_id) VALUES (1, 2) RETURNING prescription_id', 'ERR:42501');

    -- patient
    UPDATE patients SET db_username = 'pat_test_1' WHERE patient_id = 1;
    PERFORM pg_temp.tr('F', 'a patient sees their own record', 'onedose_patient', 'pat_test_1',
        'SELECT count(*) FROM patients', 'OK:1');
    PERFORM pg_temp.tr('F', 'a patient cannot see anyone else', 'onedose_patient', 'pat_test_1',
        'SELECT count(*) FROM prescription_items WHERE patient_id <> 1', 'OK:0');
    PERFORM pg_temp.tr('F', 'a patient cannot prescribe', 'onedose_patient', 'pat_test_1',
        'INSERT INTO prescriptions (patient_id, clinician_id) VALUES (1, 1) RETURNING prescription_id', 'ERR:42501');

    -- admin
    PERFORM pg_temp.tr('F', 'admin can read the audit log', 'onedose_admin', 'admin_demo',
        'SELECT (count(*) > 0)::text FROM audit_log', 'OK:true');
    PERFORM pg_temp.tr('F', 'admin cannot read patient records', 'onedose_admin', 'admin_demo',
        'SELECT count(*) FROM patients', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'admin cannot read password hashes', 'onedose_admin', 'admin_demo',
        'SELECT password_hash FROM clinicians LIMIT 1', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'admin can refresh the alert statistics', 'onedose_admin', 'admin_demo',
        'SELECT fn_refresh_alert_stats()::text', 'OK:%');
    PERFORM pg_temp.tr('F', 'admin can verify the audit chain', 'onedose_admin', 'admin_demo',
        'SELECT is_valid::text FROM fn_verify_audit_chain()', 'OK:true');

    -- scanner (card reader path)
    PERFORM pg_temp.tr('F', 'the scanner role cannot read patients', 'onedose_scanner', NULL,
        'SELECT count(*) FROM patients', 'ERR:42501');
    PERFORM pg_temp.tr('F', 'the scanner role can call fn_record_scan', 'onedose_scanner', NULL,
        $s$SELECT outcome FROM fn_record_scan(digest('DEMO-CARD-006::OneDoseDemoCardSalt2026', 'sha256'))$s$, 'OK:matched');

    -- card scan outcomes
    INSERT INTO devices (name) VALUES ('tests-reader') RETURNING device_id INTO v_dev;
    UPDATE rfid_cards SET active = false WHERE patient_id = 2;
    SELECT count(*) INTO v_n_before FROM card_scans;
    SELECT s.outcome, s.patient_id INTO v_o, v_p FROM fn_record_scan(digest('DEMO-CARD-002::OneDoseDemoCardSalt2026', 'sha256')) s;
    PERFORM pg_temp.expect('F', 'scan: a deactivated card is refused', v_o = 'inactive_card' AND v_p IS NULL, v_o);
    SELECT s.outcome, s.patient_id INTO v_o, v_p FROM fn_record_scan(digest('DEMO-CARD-005::OneDoseDemoCardSalt2026', 'sha256')) s;
    PERFORM pg_temp.expect('F', 'scan: a revoked consent is refused and no patient id is leaked', v_o = 'no_consent' AND v_p IS NULL, v_o);
    SELECT s.outcome, s.patient_id INTO v_o, v_p FROM fn_record_scan(digest('DEMO-CARD-004::OneDoseDemoCardSalt2026', 'sha256')) s;
    PERFORM pg_temp.expect('F', 'scan: an expired consent is refused', v_o = 'no_consent' AND v_p IS NULL, v_o);
    SELECT s.outcome, s.patient_id INTO v_o, v_p FROM fn_record_scan(digest('NOT-A-REAL-CARD', 'sha256')) s;
    PERFORM pg_temp.expect('F', 'scan: an unknown card is refused', v_o = 'unknown_card' AND v_p IS NULL, v_o);
    SELECT s.outcome, s.patient_id INTO v_o, v_p FROM fn_record_scan(digest('DEMO-CARD-001::OneDoseDemoCardSalt2026', 'sha256'), 'tests-reader') s;
    PERFORM pg_temp.expect('F', 'scan: a valid card returns the patient', v_o = 'matched' AND v_p = 1, v_o || ' / patient ' || coalesce(v_p::text, 'null'));
    PERFORM pg_temp.t('F', 'every scan was logged and the device last_seen_at was updated',
        format($q$ SELECT (SELECT count(*) FROM card_scans) - %s = 5 AND (SELECT last_seen_at IS NOT NULL FROM devices WHERE name = 'tests-reader'),
                         ((SELECT count(*) FROM card_scans) - %s)::text || ' new scan rows (expected 5)' $q$, v_n_before, v_n_before));
    PERFORM pg_temp.te('F', 'scan: a hash that is not 32 bytes is rejected', $q$ SELECT * FROM fn_record_scan('\x1234'::bytea) $q$, '22023');
    PERFORM pg_temp.te('F', 'scan: an unknown device name is rejected',
        $q$ SELECT * FROM fn_record_scan(digest('DEMO-CARD-001::OneDoseDemoCardSalt2026', 'sha256'), 'no-such-device') $q$, '22023');
    PERFORM pg_temp.tr('F', 'v_latest_scan gives the clinician the patient who just tapped', 'onedose_clinician', 'dr_demo',
        'SELECT patient_id FROM v_latest_scan', 'OK:1');
END $do$;

-- ---------------------------------------------------------------------
-- G. Views and statistics (05)
-- ---------------------------------------------------------------------
DO $do$
BEGIN
    PERFORM pg_temp.t('G', 'v_active_medications has the contract columns the API reads',
      $q$ SELECT count(*) = 10, count(*)::text || ' of 10 columns' FROM information_schema.columns
          WHERE table_name = 'v_active_medications' AND column_name IN ('patient_id', 'prescription_item_id', 'brand_id',
            'brand_name', 'ingredient_id', 'ingredient_name', 'strength_mg', 'daily_ingredient_mg', 'start_date', 'end_date') $q$);
    PERFORM pg_temp.t('G', 'v_patient_summary for Demo A: 1 allergy, active ingredients, consent',
      $q$ SELECT jsonb_array_length(allergies) = 1 AND jsonb_array_length(active_ingredients) >= 1 AND has_active_consent,
                 jsonb_array_length(allergies) || ' allergy, ' || jsonb_array_length(active_ingredients) || ' ingredients'
          FROM v_patient_summary WHERE patient_id = 1 $q$);
    PERFORM fn_refresh_alert_stats();
    PERFORM pg_temp.t('G', 'mv_alert_stats has one row per check and counts the override made earlier',
      $q$ SELECT count(*) = 5 AND bool_or(overridden_alerts >= 1), string_agg(check_type || '=' || total_alerts || '/' || overridden_alerts, ', ')
          FROM mv_alert_stats $q$);
    PERFORM pg_temp.t('G', 'override_rate_pct equals overridden / total x 100',
      $q$ SELECT bool_and(CASE WHEN total_alerts = 0 THEN override_rate_pct = 0
                               ELSE override_rate_pct = round(overridden_alerts::numeric / total_alerts * 100, 2) END), 'checked 5 rows'
          FROM mv_alert_stats $q$);
    PERFORM pg_temp.t('G', 'v_audit_recent shows at most 200 rows with an 8-character hash prefix',
      $q$ SELECT count(*) BETWEEN 1 AND 200 AND bool_and(length(hash_prefix) = 8), count(*)::text FROM v_audit_recent $q$);
END $do$;

-- ---------------------------------------------------------------------
-- H. Constraints (01)
-- ---------------------------------------------------------------------
DO $do$
BEGIN
    PERFORM pg_temp.te('H', 'interactions: the pair must be stored with the lower id first',
        $q$ INSERT INTO interactions (ingredient_a, ingredient_b, severity, source_id)
            SELECT ingredient_b, ingredient_a, 'minor', source_id FROM interactions LIMIT 1 $q$, '23514');
    PERFORM pg_temp.te('H', 'interactions: a pair cannot be stored twice',
        $q$ INSERT INTO interactions (ingredient_a, ingredient_b, severity, source_id)
            SELECT ingredient_a, ingredient_b, 'minor', source_id FROM interactions LIMIT 1 $q$, '23505');
    PERFORM pg_temp.te('H', 'an allergy needs exactly one target (none given)',
        'INSERT INTO patient_allergies (patient_id) VALUES (6)', '23514');
    PERFORM pg_temp.te('H', 'an allergy needs exactly one target (both given)',
        $q$ INSERT INTO patient_allergies (patient_id, ingredient_id, class_id) VALUES (6, 1, 1) $q$, '23514');
    PERFORM pg_temp.te('H', 'dose limit age bands of one ingredient cannot overlap',
        $q$ INSERT INTO dose_limits (ingredient_id, age_min_years, age_max_years, max_daily_mg, source_id)
            SELECT ingredient_id, age_min_years, age_max_years, max_daily_mg, source_id FROM dose_limits LIMIT 1 $q$, '23P01');
    PERFORM pg_temp.te('H', 'a card hash must be exactly 32 bytes (SHA-256)',
        $q$ INSERT INTO rfid_cards (patient_id, uid_hash) VALUES (6, '\x1234') $q$, '23514');
    PERFORM pg_temp.te('H', 'a consent must expire after it was granted',
        $q$ INSERT INTO consents (patient_id, granted_at, expires_at) VALUES (6, now(), now() - interval '1 day') $q$, '23514');
    PERFORM pg_temp.te('H', 'an item must belong to the same patient as its prescription',
        format($q$ INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day)
                  VALUES (%s, 2, %s, 1, 1) $q$, pg_temp.ctx('rx1'), pg_temp.brand('Cetzine 10')), '23503');
    PERFORM pg_temp.te('H', 'a dose must be positive',
        format($q$ INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day)
                  VALUES (%s, 1, %s, 0, 1) $q$, pg_temp.ctx('rx1'), pg_temp.brand('Dolo 650')), '23514');
END $do$;

-- =====================================================================
-- Report for sections A to H, then undo everything they did
-- =====================================================================
\echo
\echo '================  OneDose database tests  ================'
\set QUIET off
SELECT section AS "sec", status, test, left(detail, 100) AS detail FROM pg_temp.t_res ORDER BY n;
\set QUIET on
SELECT count(*) FILTER (WHERE status = 'PASS') AS pass, count(*) FILTER (WHERE status = 'FAIL') AS fail,
       count(*) FILTER (WHERE status = 'WARN') AS warn, count(*) FILTER (WHERE status = 'SKIP') AS skip
FROM pg_temp.t_res \gset main_
ROLLBACK;

-- ---------------------------------------------------------------------
-- I. Concurrency: two clinicians prescribe to ONE patient at the same moment (write skew)
--    Clinician A prescribes warfarin, clinician B prescribes Brufen. Each check runs before the other
--    commits, so neither sees the clash.
--    READ COMMITTED (naive): both commit, the clash is missed.   SERIALIZABLE: one is stopped (40001, retry).
--    These sessions COMMIT, so the data stays (see the note at the top).
-- ---------------------------------------------------------------------
SELECT set_config('tests.race_conn', :'race_conn', false) AS ignore_0 \gset
DO $do$
BEGIN
    CREATE EXTENSION IF NOT EXISTS dblink;
    PERFORM set_config('tests.race_ok', '1', false);
EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('tests.race_ok', '0', false);
    PERFORM pg_temp.expect('I', 'concurrency race test', false, 'SKIP: dblink extension is not available (' || SQLERRM || ')');
END $do$;
SELECT current_setting('tests.race_ok') = '1' AS race_ok \gset

\if :race_ok
-- committed fixture: one fresh patient per scenario, with consent and two empty prescriptions
CREATE FUNCTION pg_temp.race_fixture(p_label text) RETURNS TABLE(patient bigint, rx_a bigint, rx_b bigint)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO patients (full_name, date_of_birth, sex)
    VALUES ('RACE-TEST ' || p_label || ' ' || to_char(clock_timestamp(), 'HH24MISSMS'), current_date - 14600, 'female')
    RETURNING patient_id INTO patient;
    INSERT INTO consents (patient_id, expires_at) VALUES (patient, now() + interval '1 day');
    INSERT INTO prescriptions (patient_id, clinician_id) VALUES (patient, 1) RETURNING prescription_id INTO rx_a;
    INSERT INTO prescriptions (patient_id, clinician_id) VALUES (patient, 1) RETURNING prescription_id INTO rx_b;
    RETURN NEXT;
END $$;

CREATE FUNCTION pg_temp.race(p_patient bigint, p_rx_a bigint, p_rx_b bigint, p_iso text)
RETURNS TABLE(items integer, interaction_alerts integer, loser text, note text)
LANGUAGE plpgsql AS $$
DECLARE
    conn text := coalesce(nullif(current_setting('tests.race_conn', true), ''), 'dbname=' || current_database());
    warf integer := pg_temp.brand('Warf 5');
    bruf integer := pg_temp.brand('Brufen 400');
    v_err text := 'none';
BEGIN
    BEGIN
        BEGIN PERFORM dblink_disconnect('race_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN PERFORM dblink_disconnect('race_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM dblink_connect('race_a', conn);
        PERFORM dblink_connect('race_b', conn);
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT -1, -1, 'SKIP'::text, 'SKIP: cannot open a second connection (' || SQLERRM || '). Pass -v race_conn="dbname=... host=... user=... password=..."';
        RETURN;
    END;
    PERFORM dblink_exec('race_a', 'BEGIN ISOLATION LEVEL ' || p_iso);
    PERFORM dblink_exec('race_b', 'BEGIN ISOLATION LEVEL ' || p_iso);
    PERFORM * FROM dblink('race_a', 'SELECT 1') AS t(x int);      -- both take their snapshot now
    PERFORM * FROM dblink('race_b', 'SELECT 1') AS t(x int);
    -- A prescribes warfarin (not committed yet)
    PERFORM dblink_exec('race_a', format('INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day) VALUES (%s, %s, %s, 1, 1)', p_rx_a, p_patient, warf));
    -- B prescribes Brufen at the same moment; its check cannot see A's uncommitted item
    PERFORM dblink_send_query('race_b', format('INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day) VALUES (%s, %s, %s, 1, 3) RETURNING item_id', p_rx_b, p_patient, bruf));
    PERFORM pg_sleep(1);
    PERFORM dblink_exec('race_a', 'COMMIT');
    BEGIN
        PERFORM * FROM dblink_get_result('race_b') AS t(item_id bigint);
        PERFORM * FROM dblink_get_result('race_b') AS t(item_id bigint);
        PERFORM dblink_exec('race_b', 'COMMIT');
    EXCEPTION WHEN OTHERS THEN
        v_err := SQLSTATE;
        BEGIN PERFORM dblink_exec('race_b', 'ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
    END;
    PERFORM dblink_disconnect('race_a');
    PERFORM dblink_disconnect('race_b');
    RETURN QUERY SELECT (SELECT count(*)::integer FROM prescription_items WHERE patient_id = p_patient),
                        (SELECT count(*)::integer FROM alerts WHERE patient_id = p_patient AND check_type = 'interaction'),
                        v_err, 'second clinician ended with SQLSTATE ' || v_err;
END $$;

SELECT * FROM pg_temp.race_fixture('naive') \gset naive_
SELECT pg_temp.t('I', 'READ COMMITTED (naive): both prescriptions commit and the warfarin + ibuprofen clash is MISSED',
  format($q$ SELECT r.loser = 'SKIP' OR (r.items = 2 AND r.interaction_alerts = 0 AND r.loser = 'none'),
                    CASE WHEN r.loser = 'SKIP' THEN r.note
                         ELSE r.items || ' items saved, ' || r.interaction_alerts || ' interaction alerts, ' || r.note END
             FROM pg_temp.race(%s, %s, %s, 'READ COMMITTED') r $q$, :naive_patient, :naive_rx_a, :naive_rx_b)) AS ignore_1 \gset

SELECT * FROM pg_temp.race_fixture('serializable') \gset ser_
SELECT pg_temp.t('I', 'SERIALIZABLE: the second prescription is stopped with a retryable error (40001), so the clash cannot be missed',
  format($q$ SELECT r.loser = 'SKIP' OR (r.items = 1 AND r.loser = '40001'),
                    CASE WHEN r.loser = 'SKIP' THEN r.note
                         ELSE r.items || ' item saved, ' || r.note END
             FROM pg_temp.race(%s, %s, %s, 'SERIALIZABLE') r $q$, :ser_patient, :ser_rx_a, :ser_rx_b)) AS ignore_2 \gset
\else
\echo 'Section I skipped: dblink is not available.'
\endif

-- =====================================================================
-- Summary
-- =====================================================================
\set QUIET off
\if :race_ok
\echo
\echo '---- race test (section I) ----'
SELECT section AS "sec", status, test, left(detail, 100) AS detail FROM pg_temp.t_res ORDER BY n;
\endif
SELECT :main_pass + count(*) FILTER (WHERE status = 'PASS') AS pass,
       :main_fail + count(*) FILTER (WHERE status = 'FAIL') AS fail,
       :main_warn + count(*) FILTER (WHERE status = 'WARN') AS warn,
       :main_skip + count(*) FILTER (WHERE status = 'SKIP') AS skip
FROM pg_temp.t_res;
SELECT (:main_fail + count(*) FILTER (WHERE status = 'FAIL')) > 0 AS any_fail FROM pg_temp.t_res \gset
\if :any_fail
DO $$ BEGIN RAISE EXCEPTION 'one or more tests FAILED (see the report above)'; END $$;
\endif
