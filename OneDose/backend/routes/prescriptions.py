# File: backend/routes/prescriptions.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Prescription endpoints: GET /brands/search, POST /prescriptions/check, POST /prescriptions, POST /alerts/{id}/override. Calls SQL functions only, no safety logic here.
# Inputs: Brand text, patient id, brand id, dose, frequency, override reason.
# Outputs: Brand matches, ranked alerts with explanations, safer alternatives, saved prescription.
# Depends on: db.py, auth.py, schemas.py, llm.py
