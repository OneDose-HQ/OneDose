# MedGuard v2 (name not final)

A medicine-safety system. Every brand is stored as its ingredients, so each safety
check is a database query. The database decides; the app only shows the result.

## Who owns what
| Person | Files |
|---|---|
| Sivani | frontend/*, dbms/02, 03, 05, 06, benchmarks.sql, dbms/data/* |
| Bhavya | backend/*, hardware/*, dbms/01, 04, 07, 08, tests.sql |

The owner's name is written at the top of every file.

## How we use Git (simple version)
1. One of us creates the GitHub repo and pushes this whole folder. The other clones it.
2. Each person works on their own branch (sivani-frontend, bhavya-backend).
3. Edit only the files you own.
4. Commit often. When a file works, open a pull request into main. The other person merges it.
5. Run `git pull` on main often so you have each other's latest work.
6. Before changing a table (01_schema.sql) or an API endpoint, tell the other person.

## Prompt line for Antigravity (paste at the start of every prompt)
Edit only [FILE PATH]. Do not create or rename files. Follow AGENTS.md.

## Notes
- dbms/data/*.csv headers are a proposal. They must match 01_schema.sql.
- Database engine not final (PostgreSQL planned, MySQL possible). Check with the DBMS faculty.
- All patient data is synthetic. This is a prototype, not a medical device.
