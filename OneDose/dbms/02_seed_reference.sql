-- File: dbms/02_seed_reference.sql
-- Owner: Sivani  (only the owner edits this file)
-- Purpose: Load the drug knowledge from data/*.csv and fill the small lookup tables (drug classes, indications, conditions, sources, demo clinicians).
-- Inputs: data/*.csv.
-- Outputs: Filled reference tables.
-- Depends on: 01_schema.sql, data/*.csv

-- ---------------------------------------------------------------------
-- 1. Sources (DDInter, openFDA, WHO ATC, OneDose curated starter set)
-- ---------------------------------------------------------------------
INSERT INTO sources (source_id, name, license, url, retrieved_on, reviewed_by, reviewed_on) VALUES
(1, 'DDInter', 'CC BY-NC-SA 4.0', 'http://ddinter.scbdd.com', '2026-10-24', 'Dr. Demo Clinician', '2026-10-24'),
(2, 'openFDA label', 'open data', 'https://open.fda.gov', '2026-10-24', 'Dr. Demo Clinician', '2026-10-24'),
(3, 'openFDA label (elderly threshold applied to age 65+)', 'open data', 'https://open.fda.gov', '2026-10-24', 'Dr. Demo Clinician', '2026-10-24'),
(4, 'openFDA label (label threshold age 75 applied conservatively to elderly band 65+)', 'open data', 'https://open.fda.gov', '2026-10-24', 'Dr. Demo Clinician', '2026-10-24'),
(5, 'WHO ATC', 'open data', 'https://www.whocc.no/atc_ddd_index/', '2026-10-24', 'Pharm. Demo Pharmacist', '2026-10-24'),
(6, 'OneDose curated starter set (unverified rows need clinician review)', 'CC BY 4.0', 'https://onedose.local', '2026-10-24', 'Dr. Demo Clinician', '2026-10-24')
ON CONFLICT (source_id) DO UPDATE SET name = EXCLUDED.name;

-- ---------------------------------------------------------------------
-- 2. Ingredients (loaded from CSV)
-- ---------------------------------------------------------------------
\copy ingredients (ingredient_id, name, atc_code) FROM 'dbms/data/ingredients.csv' WITH (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------
-- 3. Drug Classes (parent/child hierarchy)
-- ---------------------------------------------------------------------
-- Top-level classes
INSERT INTO drug_classes (class_id, name, parent_class_id) VALUES
(1, 'Analgesic and anti-inflammatory', NULL),
(2, 'Antibiotic', NULL),
(3, 'Anticoagulant', NULL),
(4, 'Antiplatelet', NULL),
(5, 'Antihypertensive', NULL),
(6, 'Diuretic', NULL),
(7, 'Cardiac glycoside', NULL),
(8, 'Statin', NULL),
(9, 'Proton pump inhibitor', NULL),
(10, 'Antihistamine', NULL),
(11, 'Leukotriene antagonist', NULL),
(12, 'Opioid analgesic', NULL),
(13, 'SSRI', NULL),
(14, 'Benzodiazepine', NULL),
(15, 'Nitrate', NULL),
(16, 'PDE5 inhibitor', NULL),
(17, 'Thyroid hormone', NULL),
(18, 'Biguanide', NULL),
(19, 'Supplement', NULL),
(20, 'Decongestant', NULL),
(21, 'Immunosuppressant', NULL);

-- Sub-classes
INSERT INTO drug_classes (class_id, name, parent_class_id) VALUES
(22, 'NSAID', 1),
(23, 'Penicillin', 2),
(24, 'Macrolide', 2),
(25, 'Fluoroquinolone', 2),
(26, 'Cephalosporin', 2),
(27, 'Nitroimidazole', 2),
(28, 'ACE inhibitor', 5),
(29, 'ARB', 5),
(30, 'Calcium channel blocker', 5),
(31, 'Beta blocker', 5),
(32, 'Loop diuretic', 6),
(33, 'Potassium-sparing diuretic', 6);

-- Grandchild classes (Beta blocker subtypes)
INSERT INTO drug_classes (class_id, name, parent_class_id) VALUES
(34, 'Non-selective beta blocker', 31),
(35, 'Cardioselective beta blocker', 31);

-- ---------------------------------------------------------------------
-- 4. Ingredient Classes (most specific class mapping)
-- ---------------------------------------------------------------------
INSERT INTO ingredient_classes (ingredient_id, class_id) VALUES
(1, 1),   -- paracetamol -> Analgesic and anti-inflammatory
(2, 22),  -- ibuprofen -> NSAID
(3, 22),  -- diclofenac -> NSAID
(4, 22),  -- aspirin -> NSAID
(5, 23),  -- amoxicillin -> Penicillin
(6, 23),  -- clavulanic acid -> Penicillin
(7, 24),  -- azithromycin -> Macrolide
(8, 25),  -- ciprofloxacin -> Fluoroquinolone
(9, 26),  -- cefixime -> Cephalosporin
(10, 27), -- metronidazole -> Nitroimidazole
(11, 24), -- clarithromycin -> Macrolide
(12, 3),  -- warfarin -> Anticoagulant
(13, 4),  -- clopidogrel -> Antiplatelet
(14, 30), -- amlodipine -> Calcium channel blocker
(15, 29), -- losartan -> ARB
(16, 29), -- telmisartan -> ARB
(17, 28), -- enalapril -> ACE inhibitor
(18, 35), -- metoprolol -> Cardioselective beta blocker
(19, 35), -- atenolol -> Cardioselective beta blocker
(20, 34), -- propranolol -> Non-selective beta blocker
(21, 30), -- verapamil -> Calcium channel blocker
(22, 32), -- furosemide -> Loop diuretic
(23, 33), -- spironolactone -> Potassium-sparing diuretic
(24, 7),  -- digoxin -> Cardiac glycoside
(25, 8),  -- atorvastatin -> Statin
(26, 8),  -- simvastatin -> Statin
(27, 18), -- metformin -> Biguanide
(28, 9),  -- pantoprazole -> Proton pump inhibitor
(29, 9),  -- omeprazole -> Proton pump inhibitor
(30, 17), -- levothyroxine -> Thyroid hormone
(31, 10), -- cetirizine -> Antihistamine
(32, 10), -- levocetirizine -> Antihistamine
(33, 10), -- fexofenadine -> Antihistamine
(34, 11), -- montelukast -> Leukotriene antagonist
(35, 20), -- phenylephrine -> Decongestant
(36, 10), -- chlorpheniramine -> Antihistamine
(37, 12), -- tramadol -> Opioid analgesic
(38, 13), -- sertraline -> SSRI
(39, 14), -- alprazolam -> Benzodiazepine
(40, 16), -- sildenafil -> PDE5 inhibitor
(41, 15), -- isosorbide mononitrate -> Nitrate
(42, 19), -- calcium carbonate -> Supplement
(43, 19), -- cholecalciferol -> Supplement
(44, 21); -- methotrexate -> Immunosuppressant

-- ---------------------------------------------------------------------
-- 5. Indications
-- ---------------------------------------------------------------------
INSERT INTO indications (indication_id, name) VALUES
(1, 'pain'),
(2, 'fever'),
(3, 'inflammation'),
(4, 'bacterial infection'),
(5, 'anaerobic infection'),
(6, 'hypertension'),
(7, 'angina'),
(8, 'heart failure'),
(9, 'high cholesterol'),
(10, 'type 2 diabetes'),
(11, 'acid reflux'),
(12, 'hypothyroidism'),
(13, 'allergic rhinitis'),
(14, 'asthma'),
(15, 'blood clot prevention'),
(16, 'depression'),
(17, 'anxiety'),
(18, 'erectile dysfunction'),
(19, 'calcium deficiency'),
(20, 'rheumatoid arthritis'),
(21, 'edema');

-- ---------------------------------------------------------------------
-- 6. Ingredient Indications (Line of Therapy, starter data needing clinician review)
-- ---------------------------------------------------------------------
INSERT INTO ingredient_indications (ingredient_id, indication_id, line_of_therapy) VALUES
-- Pain & Fever alternatives
(1, 1, 1), (1, 2, 1),   -- paracetamol (1st line)
(2, 1, 2), (2, 2, 2),   -- ibuprofen (2nd line alternative)
(2, 3, 1),              -- ibuprofen (inflammation 1st line)
(3, 1, 2), (3, 3, 1),   -- diclofenac
(4, 1, 2), (4, 15, 1),  -- aspirin (pain 2nd line, clot prevention 1st line)
-- Bacterial infection alternatives
(5, 4, 1), (6, 4, 1),   -- amoxicillin + clavulanic acid (1st line)
(7, 4, 2),              -- azithromycin (2nd line)
(8, 4, 2),              -- ciprofloxacin (2nd line)
(9, 4, 2),              -- cefixime (2nd line)
(11, 4, 2),             -- clarithromycin (2nd line)
(10, 5, 1),             -- metronidazole (anaerobic infection)
-- Anticoagulation / antiplatelet
(12, 15, 1),            -- warfarin
(13, 15, 1),            -- clopidogrel
-- Hypertension alternatives
(14, 6, 1),             -- amlodipine (1st line)
(15, 6, 1),             -- losartan (1st line)
(16, 6, 1),             -- telmisartan (1st line)
(17, 6, 1), (17, 8, 1), -- enalapril (hypertension 1st line, HF 1st line)
(18, 6, 2), (18, 7, 2), -- metoprolol
(19, 6, 2),             -- atenolol
(20, 6, 2), (20, 7, 2), -- propranolol
(21, 6, 2), (21, 7, 1), -- verapamil (angina 1st line)
(41, 7, 1),             -- isosorbide mononitrate (angina 1st line)
-- Diuretics & Cardiac
(22, 21, 1), (22, 8, 2),-- furosemide (edema 1st line, HF 2nd line)
(23, 8, 2), (23, 21, 2),-- spironolactone
(24, 8, 2),             -- digoxin (HF 2nd line)
-- Lipid lowering alternatives
(25, 9, 1),             -- atorvastatin (1st line)
(26, 9, 2),             -- simvastatin (2nd line)
-- Metabolic & Endocrine
(27, 10, 1),            -- metformin (1st line diabetes)
(30, 12, 1),            -- levothyroxine (1st line hypothyroidism)
-- Acid reflux alternatives
(28, 11, 1),            -- pantoprazole (1st line)
(29, 11, 1),            -- omeprazole (1st line)
-- Allergic rhinitis alternatives
(31, 13, 1),            -- cetirizine (1st line)
(32, 13, 1),            -- levocetirizine (1st line)
(33, 13, 2),            -- fexofenadine (2nd line)
(34, 13, 2), (34, 14, 2), -- montelukast (allergic rhinitis 2nd line, asthma 2nd line)
(35, 13, 2),            -- phenylephrine
(36, 13, 2),            -- chlorpheniramine
-- Neuropsychiatric & other
(37, 1, 2),             -- tramadol (pain 2nd line)
(38, 16, 1),            -- sertraline (depression 1st line)
(39, 17, 1),            -- alprazolam (anxiety 1st line)
(40, 18, 1),            -- sildenafil (erectile dysfunction 1st line)
(42, 19, 1),            -- calcium carbonate (calcium deficiency)
(43, 19, 1),            -- cholecalciferol
(44, 20, 1);            -- methotrexate (rheumatoid arthritis)

-- ---------------------------------------------------------------------
-- 7. Conditions (ICD-10 coded reference)
-- ---------------------------------------------------------------------
INSERT INTO conditions (condition_id, icd10_code, name) VALUES
(1, 'K27', 'peptic ulcer disease'),
(2, 'N18', 'chronic kidney disease'),
(3, 'N18.5', 'severe renal impairment'),
(4, 'I50', 'heart failure'),
(5, 'J45', 'asthma'),
(6, 'Z33', 'pregnancy'),
(7, 'G40', 'epilepsy'),
(8, 'K76', 'liver disease'),
(9, 'I10', 'hypertension'),
(10, 'E11', 'type 2 diabetes'),
(11, 'E03.9', 'hypothyroidism'),
(12, 'E78.0', 'high cholesterol'),
(13, 'J30.4', 'allergic rhinitis'),
(14, 'I20', 'angina'),
(15, 'F32', 'depression'),
(16, 'F41.9', 'anxiety');

-- ---------------------------------------------------------------------
-- 8. Brands & Brand Ingredients (loaded from CSV)
-- ---------------------------------------------------------------------
\copy brands (brand_id, brand_name, manufacturer, form, strength) FROM 'dbms/data/brands.csv' WITH (FORMAT csv, HEADER true);
\copy brand_ingredients (brand_id, ingredient_id, strength_mg) FROM 'dbms/data/brand_ingredients.csv' WITH (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------
-- 9. Drug Interactions (staged from CSV and linked to sources)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE stage_interactions (
    ingredient_a integer,
    ingredient_b integer,
    severity severity_level,
    mechanism text,
    management text,
    source text
);

\copy stage_interactions FROM 'dbms/data/interactions.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO interactions (ingredient_a, ingredient_b, severity, mechanism, management, source_id)
SELECT
    s.ingredient_a,
    s.ingredient_b,
    s.severity,
    s.mechanism,
    s.management,
    src.source_id
FROM stage_interactions s
JOIN sources src ON src.name = s.source;

DROP TABLE stage_interactions;

-- ---------------------------------------------------------------------
-- 10. Contraindications (staged from CSV, conditions and sources resolved)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE stage_contraindications (
    ingredient_id integer,
    condition_name text,
    severity severity_level,
    source text
);

\copy stage_contraindications FROM 'dbms/data/contraindications.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO contraindications (ingredient_id, condition_id, severity, note, source_id)
SELECT
    s.ingredient_id,
    c.condition_id,
    s.severity,
    NULL,
    src.source_id
FROM stage_contraindications s
JOIN conditions c ON c.name = s.condition_name
JOIN sources src ON src.name = s.source;

DROP TABLE stage_contraindications;

-- ---------------------------------------------------------------------
-- 11. Dose Limits (staged from CSV, non-overlapping age bands)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE stage_dose_limits (
    ingredient_id integer,
    age_min_years integer,
    age_max_years integer,
    max_daily_mg numeric(10,2),
    source text
);

\copy stage_dose_limits FROM 'dbms/data/dose_limits.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO dose_limits (ingredient_id, age_min_years, age_max_years, max_daily_mg, source_id)
SELECT
    s.ingredient_id,
    s.age_min_years,
    s.age_max_years,
    s.max_daily_mg,
    src.source_id
FROM stage_dose_limits s
JOIN sources src ON src.name = s.source;

DROP TABLE stage_dose_limits;

-- ---------------------------------------------------------------------
-- 12. Demo Clinicians
--     Demo accounts and plain passwords (for pitch / prototype testing only):
--       dr_demo:    'clinician123'
--       pharm_demo: 'pharm123'
--       admin_demo: 'admin123'
-- ---------------------------------------------------------------------
INSERT INTO clinicians (clinician_id, full_name, role, db_username, email, password_hash, active) VALUES
(1, 'Dr. Demo Clinician', 'clinician', 'dr_demo', 'dr_demo@onedose.local', crypt('clinician123', gen_salt('bf')), true),
(2, 'Pharm. Demo Pharmacist', 'pharmacist', 'pharm_demo', 'pharm_demo@onedose.local', crypt('pharm123', gen_salt('bf')), true),
(3, 'Admin Demo User', 'admin', 'admin_demo', 'admin_demo@onedose.local', crypt('admin123', gen_salt('bf')), true);

-- ---------------------------------------------------------------------
-- 13. Sequence Resets (sync identity sequences with loaded manual IDs)
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('sources', 'source_id'), coalesce(max(source_id), 1)) FROM sources;
SELECT setval(pg_get_serial_sequence('ingredients', 'ingredient_id'), coalesce(max(ingredient_id), 1)) FROM ingredients;
SELECT setval(pg_get_serial_sequence('drug_classes', 'class_id'), coalesce(max(class_id), 1)) FROM drug_classes;
SELECT setval(pg_get_serial_sequence('indications', 'indication_id'), coalesce(max(indication_id), 1)) FROM indications;
SELECT setval(pg_get_serial_sequence('conditions', 'condition_id'), coalesce(max(condition_id), 1)) FROM conditions;
SELECT setval(pg_get_serial_sequence('brands', 'brand_id'), coalesce(max(brand_id), 1)) FROM brands;
SELECT setval(pg_get_serial_sequence('clinicians', 'clinician_id'), coalesce(max(clinician_id), 1)) FROM clinicians;
