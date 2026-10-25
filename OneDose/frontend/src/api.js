// File: src/api.js - HTTP client with Axios, JWT interceptors, and comprehensive mock mode fallback
import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api',
  timeout: 8000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor: inject JWT
api.interceptors.request.use((config) => {
  try {
    const rawAuth = localStorage.getItem('onedose_auth');
    if (rawAuth) {
      const { token } = JSON.parse(rawAuth);
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
    }
  } catch (err) {
    // Ignore JSON parse errors
  }
  return config;
});

// Response interceptor: handle 401 redirect
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      localStorage.removeItem('onedose_auth');
      if (window.location.pathname !== '/login') {
        window.location.href = '/login';
      }
    }
    return Promise.reject(error);
  }
);

// ---------------------------------------------------------------------
// MOCK DATA STORE
// ---------------------------------------------------------------------
const isMockMode = import.meta.env.VITE_USE_MOCK === 'true';
// Fake data is used ONLY when VITE_USE_MOCK=true. If the real server cannot be reached the user must be told,
// never shown invented patients, alerts or a "saved" message.
const NETWORK_ERROR = 'Cannot reach the OneDose server. Check your connection and try again.';

const delay = (ms = 350) => new Promise((resolve) => setTimeout(resolve, ms));

const MOCK_PATIENTS = [
  {
    patient_id: 10482,
    id: 10482,
    full_name: 'Meera Nair',
    date_of_birth: '1958-03-14',
    age_years: 68,
    sex: 'female',
    initials: 'MN',
    card_id: 'A4F9-22C1',
    has_active_consent: true,
    consent_status: 'Consent active until 14 Mar 2027',
    allergies: [
      { name: 'Penicillin class', severity: 'critical', reaction: 'Anaphylaxis' },
      { name: 'Sulfonamides', severity: 'major', reaction: 'Severe rash' },
    ],
    conditions: [
      { name: 'Hypertension', icd10: 'I10' },
      { name: 'Type 2 diabetes', icd10: 'E11' },
      { name: 'CKD stage 3', icd10: 'N18.3' },
    ],
    active_medications: [
      {
        prescription_item_id: 101,
        brand_name: 'Glycomet 500',
        brand_id: 28,
        ingredients: [{ name: 'metformin', strength_mg: 500 }],
        dose: 500,
        frequency: 'BD',
        dose_frequency: '500 mg - BD',
        start_date: '2024-02-10',
        end_date: null,
      },
      {
        prescription_item_id: 102,
        brand_name: 'Ecosprin 75',
        brand_id: 7,
        ingredients: [{ name: 'aspirin', strength_mg: 75 }],
        dose: 75,
        frequency: 'OD',
        dose_frequency: '75 mg - OD',
        start_date: '2024-04-15',
        end_date: null,
      },
      {
        prescription_item_id: 103,
        brand_name: 'Amlokind 5',
        brand_id: 16,
        ingredients: [{ name: 'amlodipine', strength_mg: 5 }],
        dose: 5,
        frequency: 'OD',
        dose_frequency: '5 mg - OD',
        start_date: '2024-01-20',
        end_date: null,
      },
      {
        prescription_item_id: 104,
        brand_name: 'Pantocid 40',
        brand_id: 29,
        ingredients: [{ name: 'pantoprazole', strength_mg: 40 }],
        dose: 40,
        frequency: 'OD',
        dose_frequency: '40 mg - OD',
        start_date: '2024-06-01',
        end_date: null,
      },
    ],
  },
  {
    patient_id: 10483,
    id: 10483,
    full_name: 'Arun Patel',
    date_of_birth: '1981-07-22',
    age_years: 45,
    sex: 'male',
    initials: 'AP',
    card_id: 'B7C2-91D4',
    has_active_consent: true,
    consent_status: 'Consent active until 28 Dec 2026',
    allergies: [],
    conditions: [{ name: 'Tension headache', icd10: 'G44.2' }],
    active_medications: [
      {
        prescription_item_id: 201,
        brand_name: 'Dolo 650',
        brand_id: 1,
        ingredients: [{ name: 'paracetamol', strength_mg: 650 }],
        dose: 650,
        frequency: 'TDS',
        dose_frequency: '650 mg - TDS',
        start_date: '2024-08-01',
        end_date: null,
      },
    ],
  },
  {
    patient_id: 10484,
    id: 10484,
    full_name: 'Priya Sharma',
    date_of_birth: '1998-11-05',
    age_years: 28,
    sex: 'female',
    initials: 'PS',
    card_id: 'C3E8-44A9',
    has_active_consent: true,
    consent_status: 'Consent active until 05 Nov 2026',
    allergies: [],
    conditions: [{ name: 'Pregnancy', icd10: 'Z33' }],
    active_medications: [],
  },
];

const MOCK_BRANDS = [
  {
    brand_id: 4,
    brand_name: 'Combiflam',
    form: 'tablet',
    strength: '400 mg + 325 mg',
    ingredients: [
      { name: 'ibuprofen', strength_mg: 400 },
      { name: 'paracetamol', strength_mg: 325 },
    ],
  },
  {
    brand_id: 50,
    brand_name: 'Combiflam Plus',
    form: 'tablet',
    strength: '400 mg + 325 mg + caffeine 30 mg',
    ingredients: [
      { name: 'ibuprofen', strength_mg: 400 },
      { name: 'paracetamol', strength_mg: 325 },
      { name: 'caffeine', strength_mg: 30 },
    ],
  },
  {
    brand_id: 1,
    brand_name: 'Dolo 650',
    form: 'tablet',
    strength: '650 mg',
    ingredients: [{ name: 'paracetamol', strength_mg: 650 }],
  },
  {
    brand_id: 2,
    brand_name: 'Crocin 500',
    form: 'tablet',
    strength: '500 mg',
    ingredients: [{ name: 'paracetamol', strength_mg: 500 }],
  },
  {
    brand_id: 3,
    brand_name: 'Calpol 500',
    form: 'tablet',
    strength: '500 mg',
    ingredients: [{ name: 'paracetamol', strength_mg: 500 }],
  },
  {
    brand_id: 7,
    brand_name: 'Ecosprin 75',
    form: 'tablet',
    strength: '75 mg',
    ingredients: [{ name: 'aspirin', strength_mg: 75 }],
  },
  {
    brand_id: 9,
    brand_name: 'Augmentin 625',
    form: 'tablet',
    strength: '500 mg + 125 mg',
    ingredients: [
      { name: 'amoxicillin', strength_mg: 500 },
      { name: 'clavulanic acid', strength_mg: 125 },
    ],
  },
  {
    brand_id: 10,
    brand_name: 'Azithral 500',
    form: 'tablet',
    strength: '500 mg',
    ingredients: [{ name: 'azithromycin', strength_mg: 500 }],
  },
  {
    brand_id: 11,
    brand_name: 'Ciplox 500',
    form: 'tablet',
    strength: '500 mg',
    ingredients: [{ name: 'ciprofloxacin', strength_mg: 500 }],
  },
  {
    brand_id: 16,
    brand_name: 'Amlokind 5',
    form: 'tablet',
    strength: '5 mg',
    ingredients: [{ name: 'amlodipine', strength_mg: 5 }],
  },
  {
    brand_id: 18,
    brand_name: 'Telma 40',
    form: 'tablet',
    strength: '40 mg',
    ingredients: [{ name: 'telmisartan', strength_mg: 40 }],
  },
  {
    brand_id: 28,
    brand_name: 'Glycomet 500',
    form: 'tablet',
    strength: '500 mg',
    ingredients: [{ name: 'metformin', strength_mg: 500 }],
  },
  {
    brand_id: 29,
    brand_name: 'Pantocid 40',
    form: 'tablet',
    strength: '40 mg',
    ingredients: [{ name: 'pantoprazole', strength_mg: 40 }],
  },
  {
    brand_id: 38,
    brand_name: 'Montair-LC',
    form: 'tablet',
    strength: '10 mg + 5 mg',
    ingredients: [
      { name: 'montelukast', strength_mg: 10 },
      { name: 'levocetirizine', strength_mg: 5 },
    ],
  },
  {
    brand_id: 42,
    brand_name: 'Zoloft 50',
    form: 'tablet',
    strength: '50 mg',
    ingredients: [{ name: 'sertraline', strength_mg: 50 }],
  },
];

// ---------------------------------------------------------------------
// EXPORTED API METHODS
// ---------------------------------------------------------------------

export async function login(email, password) {
  if (isMockMode) {
    await delay(400);
    const role = email.includes('admin') ? 'admin' : email.includes('pharm') ? 'pharmacist' : 'clinician';
    const name = role === 'admin' ? 'Admin User' : role === 'pharmacist' ? 'Pharm. Verma' : 'Dr. Rao';
    return {
      token: 'mock-jwt-token-onedose-2026',
      user: { name, role, email },
    };
  }

  try {
    const res = await api.post('/auth/login', { email, password });
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Login failed');
  }
}

export async function scanCard(hashedUid) {
  if (isMockMode) {
    await delay(350);
    const clean = (hashedUid || '').trim().toUpperCase();
    const found = MOCK_PATIENTS.find((p) => p.card_id === clean) || MOCK_PATIENTS[0];
    return { patient: found };
  }

  try {
    const res = await api.post('/scan', { uid_hash: hashedUid });
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Card scan failed');
  }
}

// The card reader posts to /scan and gets no patient back; the dashboard polls this to pick up the tap.
export async function getLatestScan() {
  if (isMockMode) return { scan_id: null, patient: null };
  const res = await api.get('/scan/latest');
  return res.data;
}

export async function getPatient(id) {
  if (isMockMode) {
    await delay(250);
    const pat = MOCK_PATIENTS.find((p) => p.id === Number(id)) || MOCK_PATIENTS[0];
    return pat;
  }

  try {
    const res = await api.get(`/patients/${id}`);
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Failed to fetch patient');
  }
}

export async function getMedications(patientId, asOfDate) {
  if (isMockMode) {
    await delay(300);
    const pat = MOCK_PATIENTS.find((p) => p.id === Number(patientId)) || MOCK_PATIENTS[0];
    if (asOfDate) {
      const targetTime = new Date(asOfDate).getTime();
      return pat.active_medications.filter((m) => {
        const start = new Date(m.start_date).getTime();
        const end = m.end_date ? new Date(m.end_date).getTime() : Infinity;
        return start <= targetTime && targetTime <= end;
      });
    }
    return pat.active_medications;
  }

  try {
    const params = asOfDate ? { as_of: asOfDate } : {};
    const res = await api.get(`/patients/${patientId}/medications`, { params });
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Failed to fetch medications');
  }
}

export async function searchBrands(q) {
  if (isMockMode) {
    await delay(200);
    const query = (q || '').toLowerCase().trim();
    if (!query) return [];
    return MOCK_BRANDS.filter(
      (b) =>
        b.brand_name.toLowerCase().includes(query) ||
        b.ingredients.some((i) => i.name.toLowerCase().includes(query))
    );
  }

  try {
    const res = await api.get('/brands/search', { params: { q } });
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Brand search failed');
  }
}

export async function checkPrescription(payload) {
  if (isMockMode) {
    await delay(450);
    const brandName = payload.brand?.brand_name || payload.brand_name || '';

    // If checking Combiflam for Meera Nair (Image 3 match)
    if (brandName.toLowerCase().includes('combi')) {
      return {
        alerts: [
          {
            id: 'alt-1',
            severity: 'major',
            check_type: 'interaction',
            display_type: 'Interaction',
            ingredients: ['ibuprofen', 'aspirin'],
            explanation:
              'Ibuprofen can blunt the heart-protecting effect of aspirin and raise bleeding risk in the stomach. Her aspirin 75 mg is already active.',
            source: 'DDInter',
            management: 'space doses or choose another painkiller',
            status: 'open',
          },
          {
            id: 'alt-2',
            severity: 'major',
            check_type: 'contraindication',
            display_type: 'Drug-disease',
            ingredients: ['ibuprofen', 'CKD stage 3'],
            explanation:
              'Ibuprofen can reduce kidney blood flow, which matters with her recorded kidney disease. A non-NSAID option is listed below.',
            source: 'openFDA label',
            management: 'avoid NSAID therapy in chronic kidney disease stage 3+',
            status: 'open',
          },
          {
            id: 'alt-3',
            severity: 'moderate',
            check_type: 'interaction',
            display_type: 'Interaction',
            ingredients: ['ibuprofen', 'amlodipine'],
            explanation:
              'Ibuprofen may weaken the blood-pressure-lowering effect of amlodipine, so her readings could rise.',
            source: 'DDInter',
            management: 'monitor blood pressure periodically',
            status: 'open',
          },
        ],
        alternatives: [
          {
            brand_id: 1,
            brand_name: 'Dolo 650',
            line_of_therapy: 'First line',
            ingredients: ['paracetamol 650 mg'],
            status_text: 'No conflicts with current medicines',
          },
          {
            brand_id: 2,
            brand_name: 'Crocin 500',
            line_of_therapy: 'Second line',
            ingredients: ['paracetamol 500 mg'],
            status_text: 'No conflicts with current medicines',
          },
        ],
        sql: {
          text: `SELECT * FROM fn_check_prescription(${payload.patient_id || 10482}, ${payload.brand_id || 4}, ${payload.dose || 400}, '${payload.frequency || 'TDS'}')\nORDER BY severity_rank;`,
          elapsed_ms: 12,
        },
      };
    }

    // Default no conflicts
    return {
      alerts: [],
      alternatives: [],
      sql: {
        text: `SELECT * FROM fn_check_prescription(${payload.patient_id || 10482}, ${payload.brand_id || 1}, ${payload.dose || 650}, '${payload.frequency || 'TDS'}');`,
        elapsed_ms: 8,
      },
    };
  }

  try {
    const res = await api.post('/prescriptions/check', payload);
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Prescription check failed');
  }
}

export async function createPrescription(payload) {
  if (isMockMode) {
    await delay(400);
    return {
      success: true,
      prescription_id: 5001,
      message: 'Prescription recorded successfully in database.',
    };
  }

  try {
    const res = await api.post('/prescriptions', payload);
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Failed to record prescription');
  }
}

export async function overrideAlert(alertId, reason) {
  if (isMockMode) {
    await delay(300);
    return {
      success: true,
      alert_id: alertId,
      status: 'overridden',
      override_reason: reason,
      overridden_at: new Date().toISOString(),
    };
  }

  try {
    const res = await api.post(`/alerts/${alertId}/override`, { reason });
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Failed to override alert');
  }
}

export async function getOverrideStats() {
  if (isMockMode) {
    await delay(350);
    return {
      totals: {
        alerts: 4210,
        overrides: 684,
        override_rate: 16.2,
        highest_override_check: 'Dose Limit',
      },
      per_check: [
        { check_type: 'dose_limit', label: 'Dose Limit', total: 640, overridden: 198, override_rate: 30.9 },
        { check_type: 'interaction', label: 'Interaction', total: 1840, overridden: 285, override_rate: 15.5 },
        { check_type: 'contraindication', label: 'Contraindication', total: 950, overridden: 142, override_rate: 14.9 },
        { check_type: 'allergy', label: 'Allergy', total: 520, overridden: 41, override_rate: 7.9 },
        { check_type: 'duplicate', label: 'Duplicate', total: 260, overridden: 18, override_rate: 6.9 },
      ],
      by_severity: [
        { severity: 'critical', count: 180, label: 'Critical' },
        { severity: 'major', count: 1120, label: 'Major' },
        { severity: 'moderate', count: 2040, label: 'Moderate' },
        { severity: 'minor', count: 870, label: 'Minor' },
      ],
      top_overridden: [
        { ingredient_pair: 'paracetamol (elderly band)', check_type: 'dose_limit', count: 94 },
        { ingredient_pair: 'ibuprofen × amlodipine', check_type: 'interaction', count: 76 },
        { ingredient_pair: 'tramadol (elderly band)', check_type: 'dose_limit', count: 62 },
        { ingredient_pair: 'aspirin × clopidogrel', check_type: 'interaction', count: 58 },
        { ingredient_pair: 'metformin × CKD', check_type: 'contraindication', count: 44 },
      ],
    };
  }

  try {
    const res = await api.get('/analytics/overrides');
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Failed to fetch analytics');
  }
}

export async function getAuditLog() {
  if (isMockMode) {
    await delay(300);
    return [
      {
        id: 942,
        at: new Date(Date.now() - 1000 * 60 * 12).toISOString(),
        actor: 'dr_rao',
        action: 'OVERRIDE',
        entity: 'alert:alt-1',
        hash: 'a4f92bc8',
      },
      {
        id: 941,
        at: new Date(Date.now() - 1000 * 60 * 18).toISOString(),
        actor: 'dr_rao',
        action: 'INSERT',
        entity: 'prescription:5001',
        hash: 'b17e43d1',
      },
      {
        id: 940,
        at: new Date(Date.now() - 1000 * 60 * 45).toISOString(),
        actor: 'pharm_verma',
        action: 'READ',
        entity: 'patient:10482',
        hash: '9d2f00a5',
      },
      {
        id: 939,
        at: new Date(Date.now() - 1000 * 60 * 85).toISOString(),
        actor: 'admin_demo',
        action: 'UPDATE',
        entity: 'clinician:2',
        hash: '7c8812e9',
      },
      {
        id: 938,
        at: new Date(Date.now() - 1000 * 60 * 140).toISOString(),
        actor: 'system_scan',
        action: 'INSERT',
        entity: 'card_scan:402',
        hash: 'f03b2289',
      },
    ];
  }

  try {
    const res = await api.get('/analytics/audit');
    return res.data;
  } catch (err) {
    if (!err.response) throw new Error(NETWORK_ERROR);
    throw new Error(err.response?.data?.detail || err.message || 'Failed to fetch audit log');
  }
}

export default api;
