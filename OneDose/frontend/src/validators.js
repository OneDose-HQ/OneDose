// File: src/validators.js - Form and input validation functions returning { valid, errors }

/**
 * Validates login form fields.
 * @param {Object} fields - { email, password }
 * @returns {{ valid: boolean, errors: Object }}
 */
export function validateLogin({ email, password }) {
  const errors = {};
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  if (!email || !email.trim()) {
    errors.email = 'Work email is required';
  } else if (!emailRegex.test(email.trim())) {
    errors.email = 'Please enter a valid work email address';
  }

  if (!password) {
    errors.password = 'Password is required';
  } else if (password.length < 6) {
    errors.password = 'Password must be at least 6 characters';
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
  };
}

/**
 * Validates new prescription fields.
 * @param {Object} fields - { brand, dose, frequency }
 * @returns {{ valid: boolean, errors: Object }}
 */
export function validatePrescription({ brand, dose, frequency }) {
  const errors = {};
  const validFrequencies = ['OD', 'BD', 'TDS', 'QID', 'SOS'];

  if (!brand || (typeof brand === 'object' && !brand.brand_name) || (typeof brand === 'string' && !brand.trim())) {
    errors.brand = 'Please search and select a medicine brand';
  }

  const numDose = Number(dose);
  if (dose === undefined || dose === null || dose === '' || isNaN(numDose)) {
    errors.dose = 'Dose (mg) is required';
  } else if (numDose <= 0) {
    errors.dose = 'Dose must be greater than 0 mg';
  } else if (numDose > 5000) {
    errors.dose = 'Dose cannot exceed 5,000 mg';
  }

  if (!frequency || !validFrequencies.includes(frequency)) {
    errors.frequency = 'Please select a valid frequency (OD, BD, TDS, QID, SOS)';
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
  };
}

/**
 * Validates the clinical alert override reason.
 * @param {string} text - Reason text
 * @returns {{ valid: boolean, errors: Object }}
 */
export function validateOverrideReason(text) {
  const errors = {};
  const trimmed = (text || '').trim();

  if (!trimmed) {
    errors.reason = 'An override reason is required';
  } else if (trimmed.length < 10) {
    errors.reason = 'Reason must be at least 10 characters explaining clinical justification';
  } else if (trimmed.length > 300) {
    errors.reason = 'Reason cannot exceed 300 characters';
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
  };
}

/**
 * Validates RFID or manual Patient Card ID.
 * @param {string} text - Card ID
 * @returns {{ valid: boolean, errors: Object }}
 */
export function validateCardId(text) {
  const errors = {};
  const trimmed = (text || '').trim();
  const cardRegex = /^[a-zA-Z0-9\-]{4,}$/;

  if (!trimmed) {
    errors.cardId = 'Card ID is required';
  } else if (!cardRegex.test(trimmed)) {
    errors.cardId = 'Card ID must be at least 4 alphanumeric characters (hyphens allowed)';
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
  };
}
