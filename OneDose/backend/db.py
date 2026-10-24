# File: backend/db.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: The ONLY file that talks to the database. Runs SQL functions and reads views, switches database role per request, retries on serialization failure.
# Inputs: Function or view name plus arguments.
# Outputs: Rows as dictionaries plus timing (for the SqlPeek panel).
# Depends on: config.py
