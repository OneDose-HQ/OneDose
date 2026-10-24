// File: frontend/src/pages/Prescribe.jsx
// Owner: Sivani  (only the owner edits this file)
// Purpose: Main screen. Keeps state for patient, chosen brand, dose and alerts. Polls /scan/latest to load the tapped patient. Composes PatientCard, BrandSearch, AlertPanel, SqlPeek. Prescribe stays disabled until every critical alert has an override reason or a chosen alternative.
// Inputs: Card tap result, brand, dose, frequency.
// Outputs: Alerts shown and a saved prescription.
// Depends on: api.js, validators.js, components/*
