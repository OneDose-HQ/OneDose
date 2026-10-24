# File: backend/llm.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Turn an alert row into two plain sentences with Gemini. Check the answer only mentions ingredients from the alert; otherwise return a fixed template sentence. Wording only, never a safety decision.
# Inputs: One alert row.
# Outputs: Explanation text.
# Depends on: config.py
