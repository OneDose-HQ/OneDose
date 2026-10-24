-- File: dbms/06_seed_synthetic.sql
-- Owner: Sivani  (only the owner edits this file)
-- Purpose: Generate fake patients, allergies, conditions and prescription items at scale for benchmarks. Everything here is synthetic.
-- Inputs: Reference data.
-- Outputs: Large fake dataset, then ANALYZE.
-- Depends on: 01_schema.sql, 02_seed_reference.sql

-- NOTE: Run AFTER 02_seed_reference.sql and BEFORE 07_triggers.sql
-- so safety check triggers and audit log triggers do not fire during bulk data loading.
-- All data is completely synthetic; no real persons' data.

-- =====================================================================
-- CONFIGURATION BLOCK (Scale parameters for benchmarks / laptop testing)
-- =====================================================================
-- Sizing numbers: default 100,000 patients and 10 items/patient (~1,000,000 items)
\set synthetic_patients 100000
\set items_per_patient 10

CREATE TEMP TABLE IF NOT EXISTS seed_config (
    num_patients integer NOT NULL,
    items_per_patient integer NOT NULL
);
DELETE FROM seed_config;
INSERT INTO seed_config (num_patients, items_per_patient)
VALUES (:'synthetic_patients', :'items_per_patient');

-- Ensure fully reproducible pseudo-random numbers
SELECT setseed(0.42);

-- Card salt constant for deterministic SHA-256 RFID demo card generation
-- Salt string: 'OneDoseDemoCardSalt2026'

-- =====================================================================
-- PART A: 7 Hand-made Demo Patients (Fixed IDs 1 to 7)
-- =====================================================================
INSERT INTO patients (patient_id, full_name, date_of_birth, sex, weight_kg, created_at)
OVERRIDING SYSTEM VALUE VALUES
(1, 'Demo Patient A', current_date - interval '68 years', 'male', 72.5, now() - interval '180 days'),
(2, 'Demo Patient B', current_date - interval '45 years', 'female', 61.0, now() - interval '120 days'),
(3, 'Demo Patient C', current_date - interval '62 years', 'male', 78.0, now() - interval '200 days'),
(4, 'Demo Patient D', current_date - interval '78 years', 'female', 54.5, now() - interval '90 days'),
(5, 'Demo Patient E', current_date - interval '34 years', 'female', 58.0, now() - interval '60 days'),
(6, 'Demo Patient F', current_date - interval '29 years', 'male', 68.0, now() - interval '30 days'),
(7, 'Demo Patient G', current_date - interval '28 years', 'female', 56.0, now() - interval '15 days');

-- RFID Cards for Demo Patients 1 to 7 (SHA-256 hash of card UID + salt)
INSERT INTO rfid_cards (patient_id, uid_hash, issued_at, active) VALUES
(1, digest('DEMO-CARD-001::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '180 days', true),
(2, digest('DEMO-CARD-002::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '120 days', true),
(3, digest('DEMO-CARD-003::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '200 days', true),
(4, digest('DEMO-CARD-004::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '90 days', true),
(5, digest('DEMO-CARD-005::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '60 days', true),
(6, digest('DEMO-CARD-006::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '30 days', true),
(7, digest('DEMO-CARD-007::OneDoseDemoCardSalt2026', 'sha256'), now() - interval '15 days', true);

-- Consents (valid for 365 days from grant)
INSERT INTO consents (patient_id, scope, granted_at, expires_at) VALUES
(1, 'treatment', now() - interval '30 days', now() + interval '335 days'),
(2, 'treatment', now() - interval '30 days', now() + interval '335 days'),
(3, 'treatment', now() - interval '30 days', now() + interval '335 days'),
(4, 'treatment', now() - interval '30 days', now() + interval '335 days'),
(5, 'treatment', now() - interval '30 days', now() + interval '335 days'),
(6, 'treatment', now() - interval '30 days', now() + interval '335 days'),
(7, 'treatment', now() - interval '30 days', now() + interval '335 days');

-- Allergies for Demo Patients
-- Patient 1: allergic to Penicillin class (class_id 23)
INSERT INTO patient_allergies (patient_id, class_id, reaction, severity, valid_from)
VALUES (1, 23, 'Anaphylaxis and urticaria', 'critical', current_date - interval '5 years');

-- Conditions for Demo Patients
-- Patient 3: hypertension (condition 9) and chronic kidney disease (condition 2)
-- Patient 7: pregnancy (condition 6)
INSERT INTO patient_conditions (patient_id, condition_id, valid_from) VALUES
(3, 9, current_date - interval '10 years'),
(3, 2, current_date - interval '3 years'),
(7, 6, current_date - interval '4 months');

-- Prescriptions and Items for Demo Patients (active baseline medications)
INSERT INTO prescriptions (prescription_id, patient_id, clinician_id, created_at, notes)
OVERRIDING SYSTEM VALUE VALUES
(1, 1, 1, now() - interval '30 days', 'Baseline anticoagulation management'),
(2, 2, 1, now() - interval '5 days',  'Acute headache and muscle soreness'),
(3, 3, 1, now() - interval '60 days', 'Chronic hypertension management'),
(4, 4, 1, now() - interval '10 days', 'Severe osteoarthritis pain'),
(5, 5, 1, now() - interval '90 days', 'Major depressive disorder maintenance');

-- Items:
-- 1: Patient 1 on Warf 5 (brand 48), 1 tab daily, ongoing
-- 2: Patient 2 on Dolo 650 (brand 1), 1 tab TID, ongoing
-- 3: Patient 3 on Losar 50 (brand 17), 1 tab daily, ongoing
-- 4: Patient 4 on Tramazac 50 (brand 41), 2 tabs QID (400 mg/day), ongoing -> elderly limit demo
-- 5: Patient 5 on Zoloft 50 (brand 42), 1 tab daily, ongoing
INSERT INTO prescription_items (item_id, prescription_id, patient_id, brand_id, dose_units, doses_per_day, start_date, end_date)
OVERRIDING SYSTEM VALUE VALUES
(1, 1, 1, 48, 1.0, 1.0, current_date - interval '30 days', NULL),
(2, 2, 2, 1,  1.0, 3.0, current_date - interval '5 days',  NULL),
(3, 3, 3, 17, 1.0, 1.0, current_date - interval '60 days', NULL),
(4, 4, 4, 41, 2.0, 4.0, current_date - interval '10 days', NULL),
(5, 5, 5, 42, 1.0, 1.0, current_date - interval '90 days', NULL);

-- =====================================================================
-- PART B: Bulk Synthetic Patients and Clinical History (IDs 1001+)
-- =====================================================================

-- Bulk Patients (birth years 1940 - 2015)
INSERT INTO patients (patient_id, full_name, date_of_birth, sex, weight_kg, created_at)
OVERRIDING SYSTEM VALUE
SELECT
    gs.id AS patient_id,
    'Synthetic Patient ' || gs.id AS full_name,
    (date '1940-01-01' + floor(random() * (date '2015-12-31' - date '1940-01-01'))::int) AS date_of_birth,
    (ARRAY['female'::sex_type, 'male'::sex_type, 'other'::sex_type])[1 + floor(random() * 3)::int] AS sex,
    round((45.0 + random() * 45.0)::numeric, 1) AS weight_kg,
    now() - (random() * interval '1000 days') AS created_at
FROM seed_config cfg
CROSS JOIN LATERAL generate_series(1001, 1000 + cfg.num_patients) AS gs(id);

-- Bulk Allergies (~8% of synthetic patients)
INSERT INTO patient_allergies (patient_id, ingredient_id, class_id, reaction, severity, valid_from)
SELECT
    gs.id AS patient_id,
    CASE WHEN (gs.id % 2 = 0) THEN ((gs.id % 44) + 1)::integer ELSE NULL END AS ingredient_id,
    CASE WHEN (gs.id % 2 <> 0) THEN ((gs.id % 21) + 1)::integer ELSE NULL END AS class_id,
    'Synthetic mild to moderate skin rash or allergy' AS reaction,
    (ARRAY['minor'::severity_level, 'moderate'::severity_level, 'major'::severity_level])[1 + floor(random() * 3)::int] AS severity,
    current_date - (30 + floor(random() * 800))::int AS valid_from
FROM seed_config cfg
CROSS JOIN LATERAL generate_series(1001, 1000 + cfg.num_patients) AS gs(id)
WHERE random() < 0.08;

-- Bulk Conditions (~25% of synthetic patients)
INSERT INTO patient_conditions (patient_id, condition_id, valid_from)
SELECT
    gs.id AS patient_id,
    ((gs.id % 16) + 1)::integer AS condition_id,
    current_date - (60 + floor(random() * 1200))::int AS valid_from
FROM seed_config cfg
CROSS JOIN LATERAL generate_series(1001, 1000 + cfg.num_patients) AS gs(id)
WHERE random() < 0.25;

-- Bulk Prescriptions (3 prescriptions per patient over last 3 years)
INSERT INTO prescriptions (prescription_id, patient_id, clinician_id, created_at, notes)
OVERRIDING SYSTEM VALUE
SELECT
    ((gs.id - 1001) * 3 + p_step + 10)::bigint AS prescription_id,
    gs.id AS patient_id,
    (1 + (gs.id + p_step) % 3)::integer AS clinician_id,
    now() - (interval '1 day' * (800 - p_step * 250 + (gs.id % 20))),
    'Synthetic routine prescription follow-up ' || p_step
FROM seed_config cfg
CROSS JOIN LATERAL generate_series(1001, 1000 + cfg.num_patients) AS gs(id)
CROSS JOIN LATERAL (VALUES (1), (2), (3)) AS pr(p_step);

-- Bulk Prescription Items (10 items per patient total)
-- Construction guarantees NO OVERLAPPING BRANDS for any patient:
-- brand_id = 1 + ((gs.id + it.item_idx * 5) % 49), which generates 10 distinct brands for 0..9
INSERT INTO prescription_items (
    item_id, prescription_id, patient_id, brand_id, dose_units, doses_per_day, start_date, end_date
)
OVERRIDING SYSTEM VALUE
SELECT
    ((gs.id - 1001)::bigint * 10 + it.item_idx + 10)::bigint AS item_id,
    ((gs.id - 1001) * 3 + (CASE WHEN it.item_idx < 3 THEN 1 WHEN it.item_idx < 6 THEN 2 ELSE 3 END) + 10)::bigint AS prescription_id,
    gs.id AS patient_id,
    (1 + ((gs.id + it.item_idx * 5) % 49))::integer AS brand_id,
    1.0::numeric(6,2) AS dose_units,
    (1.0 + (it.item_idx % 2))::numeric(5,2) AS doses_per_day,
    -- Non-overlapping sequential historical date periods
    CASE
        WHEN it.item_idx < 3 THEN current_date - 750 + (it.item_idx * 20)
        WHEN it.item_idx < 6 THEN current_date - 380 + ((it.item_idx - 3) * 20)
        ELSE current_date - 40 + ((it.item_idx - 6) * 10)
    END AS start_date,
    CASE
        WHEN it.item_idx < 3 THEN current_date - 700 + (it.item_idx * 20)
        WHEN it.item_idx < 6 THEN current_date - 330 + ((it.item_idx - 3) * 20)
        WHEN it.item_idx < 8 THEN current_date - 5 + ((it.item_idx - 6) * 10)
        ELSE NULL -- items 8 and 9 are active ongoing items
    END AS end_date
FROM seed_config cfg
CROSS JOIN LATERAL generate_series(1001, 1000 + cfg.num_patients) AS gs(id)
CROSS JOIN LATERAL generate_series(0, cfg.items_per_patient - 1) AS it(item_idx);

-- Synchronize Identity Sequences for user data tables
SELECT setval(pg_get_serial_sequence('patients', 'patient_id'), coalesce(max(patient_id), 1)) FROM patients;
SELECT setval(pg_get_serial_sequence('patient_allergies', 'allergy_id'), coalesce(max(allergy_id), 1)) FROM patient_allergies;
SELECT setval(pg_get_serial_sequence('patient_conditions', 'patient_condition_id'), coalesce(max(patient_condition_id), 1)) FROM patient_conditions;
SELECT setval(pg_get_serial_sequence('prescriptions', 'prescription_id'), coalesce(max(prescription_id), 1)) FROM prescriptions;
SELECT setval(pg_get_serial_sequence('prescription_items', 'item_id'), coalesce(max(item_id), 1)) FROM prescription_items;
SELECT setval(pg_get_serial_sequence('consents', 'consent_id'), coalesce(max(consent_id), 1)) FROM consents;
SELECT setval(pg_get_serial_sequence('rfid_cards', 'card_id'), coalesce(max(card_id), 1)) FROM rfid_cards;

-- Update optimizer statistics on all large tables
ANALYZE patients;
ANALYZE patient_allergies;
ANALYZE patient_conditions;
ANALYZE prescriptions;
ANALYZE prescription_items;
ANALYZE consents;
ANALYZE rfid_cards;
