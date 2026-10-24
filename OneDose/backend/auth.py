# File: backend/auth.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Login, JWT creation and checking, role guard (clinician, pharmacist, admin), scanner device-key check. Endpoint: POST /auth/login.
# Inputs: Username and password, JWT token, device key header.
# Outputs: A JWT, the current user, or an access-denied error.
# Depends on: db.py, config.py
