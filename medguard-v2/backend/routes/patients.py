# File: backend/routes/patients.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Patient and card-scan endpoints: POST /scan, GET /scan/latest, GET /patients/{id}/meds, GET /patients/{id}/meds/as-of.
# Inputs: Scan payload from the hardware, patient id, date.
# Outputs: Patient summary and medicine lists.
# Depends on: db.py, auth.py, schemas.py
