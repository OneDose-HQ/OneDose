-- File: dbms/07_triggers.sql
-- Owner: Bhavya  (only the owner edits this file)
-- Purpose: Automatic behaviour in the database: raise alerts when a prescription item is inserted, hash-chained audit log, audit triggers, block update/delete on the audit log, protect alerts from tampering.
--   1. trg_item_raise_alerts  BEFORE INSERT on prescription_items: runs fn_check_prescription and writes one alert row per finding.
--   2. trg_alert_guard        alerts: no DELETE/TRUNCATE; UPDATE only to resolve an OPEN alert (status, override_reason,
--                             resolved_by, resolved_at) or to fill in explanation. Core facts of an alert never change.
--   3. Audit: fn_audit_append (one writer, serialised by an advisory lock) -> audit_log BEFORE INSERT trigger computes
--      prev_hash and row_hash (SHA-256 chain). Row triggers audit INSERT/UPDATE/DELETE on the clinical tables.
--      fn_log_read(table, pk) records a READ (triggers cannot see SELECTs, so the API calls it).
--   4. audit_log is append-only (UPDATE, DELETE, TRUNCATE blocked). fn_verify_audit_chain() proves nothing was altered.
-- Inputs: Inserts and updates on tables.
-- Outputs: Alert rows and audit rows.
-- Depends on: 01_schema.sql, 04_check_functions.sql (and pgcrypto from 01)
--
-- Contract for backend/db.py: at the start of every request transaction run
--     SELECT set_config('onedose.user', '<login name>', true);
-- so the audit log records the real user. Without it the actor falls back to session_user.
-- The trigger functions are SECURITY DEFINER so clinicians never need INSERT rights on alerts or audit_log (08).
-- Run 07 AFTER the seed files (02, 06) so bulk loading does not fire these triggers.

-- ---------------------------------------------------------------------
-- 1. Alerts: one row per finding, written when the item is inserted
--    BEFORE INSERT means the new item is not yet in the patient's active list, so it
--    cannot clash with itself. item_id is already assigned; the FK alerts.item_id is
--    DEFERRABLE INITIALLY DEFERRED (01), so it is checked at commit, when the item exists.
--    If the item insert fails (e.g. overlapping same brand), the alerts roll back with it.
--    Inside a SERIALIZABLE transaction the reads here are tracked, which is what
--    lets the race test catch write skew.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_item_raise_alerts() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_clinician integer;
BEGIN
    SELECT p.clinician_id INTO v_clinician
    FROM prescriptions p WHERE p.prescription_id = NEW.prescription_id;

    INSERT INTO alerts (patient_id, clinician_id, brand_id, item_id, check_type, severity,
                        ingredient_id, related_ingredient_id, conflicting_item_id, mechanism, source_id)
    SELECT NEW.patient_id, v_clinician, NEW.brand_id, NEW.item_id, r.check_type, r.severity,
           r.ingredient_id, r.related_ingredient_id, r.conflicting_item_id, r.mechanism, r.source_id
    FROM fn_check_prescription(NEW.patient_id, NEW.brand_id, NEW.dose_units,
                               NEW.doses_per_day, NEW.start_date) r
    ORDER BY r.alert_rank;

    RETURN NEW;
END $$;

CREATE TRIGGER trg_items_raise_alerts
    BEFORE INSERT ON prescription_items
    FOR EACH ROW EXECUTE FUNCTION trg_item_raise_alerts();

-- ---------------------------------------------------------------------
-- 2. Alerts are tamper-proof
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_block_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'insufficient_privilege';
END $$;

CREATE OR REPLACE FUNCTION trg_alert_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status <> 'open' THEN
        RAISE EXCEPTION 'alert % is already %, it can no longer be changed', OLD.alert_id, OLD.status
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF (NEW.alert_id, NEW.patient_id, NEW.clinician_id, NEW.brand_id, NEW.item_id, NEW.check_type,
        NEW.severity, NEW.ingredient_id, NEW.related_ingredient_id, NEW.conflicting_item_id,
        NEW.mechanism, NEW.source_id, NEW.created_at)
       IS DISTINCT FROM
       (OLD.alert_id, OLD.patient_id, OLD.clinician_id, OLD.brand_id, OLD.item_id, OLD.check_type,
        OLD.severity, OLD.ingredient_id, OLD.related_ingredient_id, OLD.conflicting_item_id,
        OLD.mechanism, OLD.source_id, OLD.created_at) THEN
        RAISE EXCEPTION 'alert % is append-only: only its status, reason and explanation can be set', OLD.alert_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.status <> 'open' THEN
        NEW.resolved_at := coalesce(NEW.resolved_at, now());
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_alerts_guard_update BEFORE UPDATE ON alerts
    FOR EACH ROW EXECUTE FUNCTION trg_alert_guard();
CREATE TRIGGER trg_alerts_block_delete BEFORE DELETE ON alerts
    FOR EACH ROW EXECUTE FUNCTION trg_block_change();
CREATE TRIGGER trg_alerts_block_truncate BEFORE TRUNCATE ON alerts
    FOR EACH STATEMENT EXECUTE FUNCTION trg_block_change();

-- ---------------------------------------------------------------------
-- 3. Hash-chained audit log
--    The advisory lock is taken BEFORE the insert so identity numbers and chain
--    order agree (audit_id order = chain order, even with concurrent writers).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_payload(a audit_log) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT concat_ws('|', a.audit_id, extract(epoch FROM a.occurred_at)::text, a.actor, a.action,
                     a.table_name, coalesce(a.row_pk, ''), coalesce(a.old_data::text, ''),
                     coalesce(a.new_data::text, ''))
$$;

CREATE OR REPLACE FUNCTION trg_audit_chain() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(727001);
    SELECT l.row_hash INTO NEW.prev_hash FROM audit_log l ORDER BY l.audit_id DESC LIMIT 1;
    NEW.row_hash := digest(coalesce(NEW.prev_hash, '\x'::bytea) || convert_to(fn_audit_payload(NEW), 'UTF8'), 'sha256');
    RETURN NEW;
END $$;

CREATE TRIGGER trg_audit_log_chain BEFORE INSERT ON audit_log
    FOR EACH ROW EXECUTE FUNCTION trg_audit_chain();
CREATE TRIGGER trg_audit_log_block_change BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION trg_block_change();
CREATE TRIGGER trg_audit_log_block_truncate BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION trg_block_change();

CREATE OR REPLACE FUNCTION fn_audit_append(p_action text, p_table text, p_pk text, p_old jsonb, p_new jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(727001);
    INSERT INTO audit_log (actor, action, table_name, row_pk, old_data, new_data)
    VALUES (coalesce(nullif(current_setting('onedose.user', true), ''), session_user),
            p_action, p_table, p_pk, p_old, p_new);
END $$;

-- Row trigger: TG_ARGV[0] is the name of the primary-key column
CREATE OR REPLACE FUNCTION trg_audit_row() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_audit_append('INSERT', TG_TABLE_NAME, to_jsonb(NEW) ->> TG_ARGV[0], NULL, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM fn_audit_append('UPDATE', TG_TABLE_NAME, to_jsonb(NEW) ->> TG_ARGV[0], to_jsonb(OLD), to_jsonb(NEW));
    ELSE
        PERFORM fn_audit_append('DELETE', TG_TABLE_NAME, to_jsonb(OLD) ->> TG_ARGV[0], to_jsonb(OLD), NULL);
    END IF;
    RETURN NULL;
END $$;

-- Reads cannot be trapped by triggers: the API calls this when it shows a patient
CREATE OR REPLACE FUNCTION fn_log_read(p_table text, p_row_pk text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT fn_audit_append('READ', p_table, p_row_pk, NULL, NULL)
$$;

-- Clinical tables that are audited (clinicians is left out: it holds password hashes)
CREATE TRIGGER trg_audit_patients           AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('patient_id');
CREATE TRIGGER trg_audit_allergies          AFTER INSERT OR UPDATE OR DELETE ON patient_allergies
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('allergy_id');
CREATE TRIGGER trg_audit_conditions         AFTER INSERT OR UPDATE OR DELETE ON patient_conditions
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('patient_condition_id');
CREATE TRIGGER trg_audit_prescriptions      AFTER INSERT OR UPDATE OR DELETE ON prescriptions
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('prescription_id');
CREATE TRIGGER trg_audit_prescription_items AFTER INSERT OR UPDATE OR DELETE ON prescription_items
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('item_id');
CREATE TRIGGER trg_audit_alerts             AFTER INSERT OR UPDATE OR DELETE ON alerts
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('alert_id');
CREATE TRIGGER trg_audit_consents           AFTER INSERT OR UPDATE OR DELETE ON consents
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('consent_id');
CREATE TRIGGER trg_audit_rfid_cards         AFTER INSERT OR UPDATE OR DELETE ON rfid_cards
    FOR EACH ROW EXECUTE FUNCTION trg_audit_row('card_id');

-- ---------------------------------------------------------------------
-- 4. Prove the chain is intact (recomputes every hash and every link)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_verify_audit_chain()
RETURNS TABLE(is_valid boolean, rows_checked bigint, first_bad_audit_id bigint)
LANGUAGE sql STABLE AS $$
    WITH c AS (
        SELECT a.audit_id, a.prev_hash, a.row_hash,
               lag(a.row_hash) OVER (ORDER BY a.audit_id) AS expected_prev,
               digest(coalesce(a.prev_hash, '\x'::bytea) || convert_to(fn_audit_payload(a), 'UTF8'), 'sha256') AS calc_hash
        FROM audit_log a
    )
    SELECT NOT coalesce(bool_or(c.prev_hash IS DISTINCT FROM c.expected_prev OR c.row_hash IS DISTINCT FROM c.calc_hash), false),
           count(*),
           min(c.audit_id) FILTER (WHERE c.prev_hash IS DISTINCT FROM c.expected_prev
                                      OR c.row_hash IS DISTINCT FROM c.calc_hash)
    FROM c
$$;

-- =====================================================================
-- End of 07_triggers.sql
-- =====================================================================
