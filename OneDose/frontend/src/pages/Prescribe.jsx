// File: src/pages/Prescribe.jsx - Three-column interactive prescription safety dashboard matching Image 3
import React, { useState, useEffect, useRef } from 'react';
import { useApp } from '../App.jsx';
import PatientCard from '../components/PatientCard.jsx';
import BrandSearch from '../components/BrandSearch.jsx';
import AlertPanel from '../components/AlertPanel.jsx';
import SqlPeek from '../components/SqlPeek.jsx';
import { scanCard, getLatestScan, checkPrescription, createPrescription, overrideAlert, getPatient } from '../api.js';
import { validatePrescription, validateCardId } from '../validators.js';

export default function Prescribe() {
  const { auth, selectedPatient, setSelectedPatient, addToast } = useApp();

  const [cardIdInput, setCardIdInput] = useState('DEMO-CARD-001');
  const [selectedBrand, setSelectedBrand] = useState({
    brand_id: 4,
    brand_name: 'Combiflam',
    form: 'tablet',
    strength: '400 mg + 325 mg',
    ingredients: [
      { name: 'Ibuprofen', strength_mg: 400 },
      { name: 'Paracetamol', strength_mg: 325 },
    ],
  });

  const [dose, setDose] = useState('400');
  const [frequency, setFrequency] = useState('TDS');

  const [alerts, setAlerts] = useState([]);
  const [alternatives, setAlternatives] = useState([]);
  const [sqlData, setSqlData] = useState(null);

  const [hasChecked, setHasChecked] = useState(false);
  const [isChecking, setIsChecking] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [tapRipple, setTapRipple] = useState(false);
  const [errors, setErrors] = useState({});

  const isPharmacist = auth?.user?.role === 'pharmacist';

  // Pick up a tap on the physical card reader. The reader posts to /scan; the dashboard polls /scan/latest.
  const lastScanId = useRef(null);
  useEffect(() => {
    if (auth?.user?.role !== 'clinician') return undefined;
    let stopped = false;
    const poll = async () => {
      try {
        const res = await getLatestScan();
        if (stopped || !res || !res.scan_id) return;
        if (lastScanId.current === null) { lastScanId.current = res.scan_id; return; } // ignore a tap from before this page opened
        if (res.scan_id !== lastScanId.current && res.patient) {
          lastScanId.current = res.scan_id;
          setSelectedPatient(res.patient);
          addToast(`Card tapped: ${res.patient.full_name} loaded`, 'success');
          setAlerts([]);
          setAlternatives([]);
          setHasChecked(false);
        }
      } catch (err) {
        // the reader is optional: a failed poll is ignored, the next one tries again
      }
    };
    poll();
    const timer = setInterval(poll, 2500);
    return () => { stopped = true; clearInterval(timer); };
  }, [auth?.user?.role]);

  // Run initial check once patient and brand are both loaded to match Image 3 exactly
  useEffect(() => {
    if (selectedPatient && selectedBrand && !hasChecked) {
      handleCheckPrescription();
    }
  }, [selectedPatient]);

  const handleCardScan = async (overrideId) => {
    const targetId = overrideId || cardIdInput;
    const val = validateCardId(targetId);
    if (!val.valid) {
      addToast(val.errors.cardId, 'error');
      return;
    }

    setTapRipple(true);
    setTimeout(() => setTapRipple(false), 300);

    try {
      const { patient } = await scanCard(targetId);
      setSelectedPatient(patient);
      addToast(`Card scanned: ${patient.full_name} loaded`, 'success');
      // Reset check on new patient
      setAlerts([]);
      setAlternatives([]);
      setHasChecked(false);
    } catch (err) {
      addToast(err.message, 'error');
    }
  };

  const handleSelectDemoPatient = (e) => {
    const val = e.target.value;
    if (!val) return;
    setCardIdInput(val);
    handleCardScan(val);
  };

  const handleBrandSelect = (brand) => {
    setSelectedBrand(brand);
    // Auto-fill sensible default dose
    if (brand.ingredients && brand.ingredients.length > 0) {
      setDose(String(brand.ingredients[0].strength_mg));
    }
    // Clear previous check results
    setAlerts([]);
    setAlternatives([]);
    setHasChecked(false);
  };

  const handleCheckPrescription = async () => {
    if (!selectedPatient) {
      addToast('Please scan or select a patient first', 'error');
      return;
    }

    const val = validatePrescription({ brand: selectedBrand, dose, frequency });
    if (!val.valid) {
      setErrors(val.errors);
      return;
    }
    setErrors({});
    setIsChecking(true);

    try {
      const res = await checkPrescription({
        patient_id: selectedPatient.patient_id || selectedPatient.id,
        brand_id: selectedBrand.brand_id,
        brand_name: selectedBrand.brand_name,
        dose: Number(dose),
        frequency,
      });

      setAlerts(res.alerts || []);
      setAlternatives(res.alternatives || []);
      setSqlData(res.sql || null);
      setHasChecked(true);

      if (res.alerts?.length > 0) {
        addToast(`Check complete: ${res.alerts.length} safety conflicts identified`, 'error');
      } else {
        addToast('Check complete: No conflicts identified', 'success');
      }
    } catch (err) {
      addToast(err.message || 'Safety check failed', 'error');
    } finally {
      setIsChecking(false);
    }
  };

  const handleOverride = async (alertId, reason) => {
    try {
      await overrideAlert(alertId, reason);
      setAlerts((prev) =>
        prev.map((a) => (a.id === alertId ? { ...a, status: 'overridden', override_reason: reason } : a))
      );
      addToast('Override recorded in tamper-evident audit log', 'success');
    } catch (err) {
      addToast('Failed to record override', 'error');
    }
  };

  const handleUseAlternative = (alt) => {
    const mockBrand = {
      brand_id: alt.brand_id,
      brand_name: alt.brand_name,
      strength: alt.ingredients?.[0] || '500 mg',
      ingredients: [
        {
          name: alt.brand_name.includes('Dolo') ? 'Paracetamol' : 'Paracetamol',
          strength_mg: alt.brand_name.includes('Dolo') ? 650 : 500,
        },
      ],
    };
    setSelectedBrand(mockBrand);
    setDose(alt.brand_name.includes('Dolo') ? '650' : '500');
    addToast(`Switched to safer alternative: ${alt.brand_name}`, 'info');

    // Run check on new alternative
    checkPrescription({
      patient_id: selectedPatient?.patient_id || selectedPatient?.id,
      brand_id: mockBrand.brand_id,
      brand_name: mockBrand.brand_name,
      dose: Number(alt.brand_name.includes('Dolo') ? 650 : 500),
      frequency,
    }).then((res) => {
      setAlerts(res.alerts || []);
      setAlternatives(res.alternatives || []);
      setSqlData(res.sql || null);
      setHasChecked(true);
    });
  };

  const handleSavePrescription = async () => {
    if (isPharmacist) return;
    setIsSubmitting(true);
    try {
      await createPrescription({
        patient_id: selectedPatient.patient_id || selectedPatient.id,
        brand_id: selectedBrand.brand_id,
        dose: Number(dose),
        frequency,
        alerts,
      });
      addToast(`Prescription for ${selectedBrand.brand_name} saved successfully!`, 'success');
      // Reset form
      setHasChecked(false);
      setAlerts([]);
      setAlternatives([]);
    } catch (err) {
      addToast(err.message, 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const openAlertsCount = alerts.filter((a) => a.status !== 'overridden').length;
  const canPrescribeAnyway = hasChecked && alerts.length > 0 && openAlertsCount === 0;
  const canConfirmSafe = hasChecked && alerts.length === 0;

  return (
    <div className="app-container">
      {/* Page Header */}
      <h1 className="page-title">New prescription</h1>
      <p className="page-subtitle">
        Tap a card, pick a medicine, and OneDose checks it against the full record before it is prescribed.
      </p>

      {/* 3-Column Responsive Grid matching Image 3 */}
      <div className="prescribe-grid">
        {/* ============================================================= */}
        {/* COLUMN 1: FIND PATIENT & PATIENT CARD                         */}
        {/* ============================================================= */}
        <div>
          {/* Card Tap Section */}
          <div className="od-card">
            <span className="section-label">FIND PATIENT</span>

            <div style={{ marginBottom: '14px' }}>
              <label htmlFor="card-id-input" className="form-label">
                Card ID
              </label>
              <input
                id="card-id-input"
                type="text"
                className="form-control mono"
                value={cardIdInput}
                onChange={(e) => setCardIdInput(e.target.value)}
                placeholder="DEMO-CARD-001"
              />
            </div>

            <button
              type="button"
              className="btn-od-primary"
              style={{
                width: '100%',
                transform: tapRipple ? 'scale(0.97)' : 'scale(1)',
                transition: 'transform 120ms ease, background-color 150ms ease',
              }}
              onClick={() => handleCardScan(cardIdInput)}
            >
              Mock card tap
            </button>

            {/* Demo Patient Quick-Selector */}
            <div style={{ marginTop: '12px' }}>
              <select
                className="form-select"
                style={{ height: '36px', fontSize: '12px' }}
                onChange={handleSelectDemoPatient}
                value={selectedPatient?.card_id || ''}
              >
                <option value="">Demo patients (synthetic)...</option>
                <option value="DEMO-CARD-001">Demo A: 68 y, on warfarin, penicillin allergy</option>
                <option value="DEMO-CARD-002">Demo B: 45 y, Dolo 650 active</option>
                <option value="DEMO-CARD-003">Demo C: 62 y, kidney disease, Losar 50</option>
                <option value="DEMO-CARD-004">Demo D: 78 y, Tramazac 50</option>
                <option value="DEMO-CARD-005">Demo E: 34 y, Zoloft 50</option>
                <option value="DEMO-CARD-006">Demo F: 29 y, no medicines</option>
                <option value="DEMO-CARD-007">Demo G: 28 y, pregnant</option>
              </select>
            </div>
          </div>

          {/* Patient Card Profile */}
          <PatientCard patient={selectedPatient} />
        </div>

        {/* ============================================================= */}
        {/* COLUMN 2: MEDICINE, INGREDIENT BREAKDOWN & CONFLICT RESULT   */}
        {/* ============================================================= */}
        <div>
          <div className="od-card">
            <span className="section-label">MEDICINE</span>

            {/* Brand Search */}
            <div style={{ marginBottom: '18px' }}>
              <BrandSearch
                onSelect={handleBrandSelect}
                disabled={isPharmacist}
              />
              {errors.brand && <div className="invalid-feedback">{errors.brand}</div>}
            </div>

            {/* Ingredient Breakdown Table */}
            {selectedBrand && (
              <div style={{ marginBottom: '22px' }}>
                <span className="section-label" style={{ fontSize: '11px' }}>
                  INGREDIENT BREAKDOWN: {selectedBrand.brand_name.toUpperCase()}
                </span>

                <table
                  style={{
                    width: '100%',
                    borderCollapse: 'collapse',
                    marginTop: '8px',
                    fontSize: '13px',
                  }}
                >
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--border)' }}>
                      <th style={{ textAlign: 'left', padding: '6px 0', color: 'var(--muted)', fontWeight: 600 }}>
                        Ingredient
                      </th>
                      <th style={{ textAlign: 'right', padding: '6px 0', color: 'var(--muted)', fontWeight: 600 }}>
                        Strength
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedBrand.ingredients?.map((ingr, i) => (
                      <tr key={i} style={{ borderBottom: '1px solid var(--border)' }}>
                        <td style={{ padding: '8px 0', color: 'var(--ink)', fontWeight: 500 }}>
                          {ingr.name.charAt(0).toUpperCase() + ingr.name.slice(1)}
                        </td>
                        <td className="mono" style={{ textAlign: 'right', padding: '8px 0', color: 'var(--ink-soft)' }}>
                          {ingr.strength_mg} mg
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {/* Dose and Frequency Row */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginBottom: '20px' }}>
              <div>
                <label htmlFor="dose-input" className="form-label">
                  Dose (mg)
                </label>
                <input
                  id="dose-input"
                  type="number"
                  className={`form-control ${errors.dose ? 'is-invalid' : ''}`}
                  value={dose}
                  onChange={(e) => setDose(e.target.value)}
                  placeholder="400"
                  disabled={isPharmacist}
                />
                {errors.dose && <div className="invalid-feedback">{errors.dose}</div>}
              </div>

              <div>
                <label htmlFor="frequency-select" className="form-label">
                  Frequency
                </label>
                <select
                  id="frequency-select"
                  className={`form-select ${errors.frequency ? 'is-invalid' : ''}`}
                  value={frequency}
                  onChange={(e) => setFrequency(e.target.value)}
                  disabled={isPharmacist}
                >
                  <option value="OD">OD (Once daily)</option>
                  <option value="BD">BD (Twice daily)</option>
                  <option value="TDS">TDS (Thrice daily)</option>
                  <option value="QID">QID (Four times daily)</option>
                  <option value="SOS">SOS (As needed)</option>
                </select>
                {errors.frequency && <div className="invalid-feedback">{errors.frequency}</div>}
              </div>
            </div>

            {/* Check Prescription Button */}
            <button
              type="button"
              className="btn-od-primary"
              style={{ width: '100%', height: '44px' }}
              onClick={handleCheckPrescription}
              disabled={!selectedPatient || !selectedBrand || isChecking}
            >
              {isChecking ? 'Evaluating safety rules in SQL...' : 'Check prescription'}
            </button>
          </div>

          {/* Results Action Card */}
          {hasChecked && (
            <div>
              {alerts.length > 0 ? (
                /* Conflict card matching Image 3 */
                <div
                  className="od-card"
                  style={{
                    backgroundColor: 'var(--major-tint)',
                    borderColor: '#F5CFAF',
                    padding: '20px',
                  }}
                >
                  <div style={{ fontSize: '15px', fontWeight: 700, color: 'var(--major)', marginBottom: '6px' }}>
                    {alerts.length} conflicts found
                  </div>
                  <div style={{ fontSize: '13px', color: 'var(--ink)', lineHeight: 1.45, marginBottom: '16px' }}>
                    Each alert must be acknowledged or overridden with a reason before you can prescribe.
                  </div>

                  {!isPharmacist ? (
                    <button
                      type="button"
                      className="btn-od-secondary"
                      style={{ width: '100%', backgroundColor: '#FFFFFF', borderColor: '#CBD5E1', fontWeight: 600 }}
                      disabled={!canPrescribeAnyway || isSubmitting}
                      onClick={handleSavePrescription}
                    >
                      {openAlertsCount > 0
                        ? `Prescribe anyway (${openAlertsCount} overrides remaining)`
                        : isSubmitting
                        ? 'Recording prescription...'
                        : 'Prescribe anyway'}
                    </button>
                  ) : (
                    <div className="badge bg-secondary text-white py-2 w-100">
                      Pharmacist view: prescribing restricted
                    </div>
                  )}
                </div>
              ) : (
                /* Safe card when 0 conflicts */
                <div
                  className="od-card"
                  style={{
                    backgroundColor: 'var(--ok-tint)',
                    borderColor: '#86EFAC',
                    padding: '20px',
                  }}
                >
                  <div style={{ fontSize: '15px', fontWeight: 700, color: 'var(--ok)', marginBottom: '6px' }}>
                    ✓ No conflicts found
                  </div>
                  <div style={{ fontSize: '13px', color: 'var(--ink)', lineHeight: 1.45, marginBottom: '16px' }}>
                    The proposed prescription cleared duplicate, interaction, allergy, contraindication, and dose checks.
                  </div>

                  {!isPharmacist && (
                    <button
                      type="button"
                      className="btn-od-primary"
                      style={{ width: '100%' }}
                      disabled={isSubmitting}
                      onClick={handleSavePrescription}
                    >
                      {isSubmitting ? 'Recording prescription...' : 'Confirm & prescribe'}
                    </button>
                  )}
                </div>
              )}
            </div>
          )}
        </div>

        {/* ============================================================= */}
        {/* COLUMN 3: SAFETY ALERTS & SAFER ALTERNATIVES                  */}
        {/* ============================================================= */}
        <div className="prescribe-col-alerts">
          <AlertPanel
            alerts={alerts}
            alternatives={alternatives}
            onOverride={handleOverride}
            onUseAlternative={handleUseAlternative}
            readOnly={isPharmacist}
          />
        </div>
      </div>

      {/* ============================================================= */}
      {/* BOTTOM DRAWER: SQL PEEK                                       */}
      {/* ============================================================= */}
      <SqlPeek sql={sqlData} />
    </div>
  );
}
