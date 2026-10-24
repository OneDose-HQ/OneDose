# AGENTS.md  (rules for AI coding agents)

Project: medicine-safety system (MedGuard v2, name not final).
Folders: frontend/  backend/  dbms/  hardware/

## Rules
1. The file tree already exists. Edit ONLY the file(s) named in the prompt.
   Never create, rename or delete files. If a new file seems needed, stop and ask.
2. Safety logic lives only in dbms/*.sql. backend/ and frontend/ contain none.
3. Every file starts with a header comment (File, Owner, Purpose, Inputs, Outputs,
   Depends on). Keep it, and update it if the job changes.
4. Keep each file under about 150 lines (the SQL function files may be longer).
5. Never put secrets in code. Use .env (see .env.example).

## frontend/ (Sivani): allowed technologies ONLY
HTML5, CSS3 (flexbox, grid), Bootstrap 5, JavaScript ES6+ (arrow functions,
promises, async/await), React (useState, useEffect, react-router-dom),
Axios, Chart.js, JWT stored in localStorage.
Not allowed: TypeScript, Tailwind, Context API, Redux, Recharts, any other library.

## backend/ (Bhavya)
Thin layer: check who the user is, call ONE SQL function or view, return JSON.
All database access goes through backend/db.py.

## dbms/
Run order: 01 to 08. The seed files (02, 06) load before triggers (07) and
security (08) on purpose. The database engine is not final (PostgreSQL planned,
MySQL possible): ask before using engine-specific features.

## Who owns what
Sivani: frontend/*, dbms/02_seed_reference.sql, dbms/03_lookup_functions.sql,
        dbms/05_views.sql, dbms/06_seed_synthetic.sql, dbms/benchmarks.sql, dbms/data/*
Bhavya: backend/*, hardware/*, dbms/01_schema.sql, dbms/04_check_functions.sql,
        dbms/07_triggers.sql, dbms/08_security.sql, dbms/tests.sql
Only edit your own files. Message the other person before changing a table or an API endpoint.
