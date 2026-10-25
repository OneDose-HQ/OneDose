// File: src/pages/PatientHistory.jsx - Historical medication timeline with 2-year date slider and active interval visualization
import React, { useState, useEffect, useMemo, useRef } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useApp } from '../App.jsx';
import { getPatient, getMedications } from '../api.js';

export default function PatientHistory() {
  const { patientId } = useParams();
  const { selectedPatient, setSelectedPatient, addToast } = useApp();

  const [patient, setPatient] = useState(selectedPatient);
  const [medications, setMedications] = useState([]);
  const [isLoading, setIsLoading] = useState(false);

  // Time-travel date calculation (2 years ago to today in days)
  const today = useMemo(() => new Date(), []);
  const twoYearsAgo = useMemo(() => {
    const d = new Date();
    d.setFullYear(d.getFullYear() - 2);
    return d;
  }, []);

  const totalDays = useMemo(() => {
    return Math.round((today.getTime() - twoYearsAgo.getTime()) / (1000 * 60 * 60 * 24));
  }, [today, twoYearsAgo]);

  // Current slider offset (0 = 2 years ago, totalDays = today)
  const [sliderDay, setSliderDay] = useState(totalDays);
  const debounceTimer = useRef(null);

  const selectedDate = useMemo(() => {
    const d = new Date(twoYearsAgo);
    d.setDate(d.getDate() + sliderDay);
    return d;
  }, [twoYearsAgo, sliderDay]);

  const selectedDateStr = useMemo(() => {
    return selectedDate.toISOString().split('T')[0];
  }, [selectedDate]);

  // Load patient if needed from route
  useEffect(() => {
    const targetId = patientId || selectedPatient?.patient_id || selectedPatient?.id;
    if (!targetId) return;
    if (!patient || (patient.id !== Number(targetId) && patient.patient_id !== Number(targetId))) {
      getPatient(targetId).then((data) => {
        setPatient(data);
        if (!selectedPatient) setSelectedPatient(data);
      });
    }
  }, [patientId]);

  // Load medications when selectedDateStr or patient changes with 300ms debounce
  useEffect(() => {
    if (!patient) return;
    const targetId = patient.patient_id || patient.id;

    clearTimeout(debounceTimer.current);
    debounceTimer.current = setTimeout(async () => {
      setIsLoading(true);
      try {
        const meds = await getMedications(targetId, selectedDateStr);
        setMedications(meds);
      } catch (err) {
        addToast(err.message, 'error');
      } finally {
        setIsLoading(false);
      }
    }, 300);

    return () => clearTimeout(debounceTimer.current);
  }, [patient, selectedDateStr]);

  const handleResetToday = () => {
    setSliderDay(totalDays);
  };

  // Convert a date string to a timeline position percentage [0..100]
  const dateToPercent = (dateStr) => {
    if (!dateStr) return 100;
    const t = new Date(dateStr).getTime();
    const pct = ((t - twoYearsAgo.getTime()) / (today.getTime() - twoYearsAgo.getTime())) * 100;
    return Math.max(0, Math.min(100, pct));
  };

  const selectedDatePercent = (sliderDay / totalDays) * 100;

  return (
    <div className="app-container">
      {/* Navigation Breadcrumb & Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
        <div>
          <h1 className="page-title">Patient Medication History</h1>
          <p className="page-subtitle" style={{ margin: 0 }}>
            Inspect historical treatments, continuous therapy intervals, and active prescriptions across time.
          </p>
        </div>
        <Link to="/prescribe" className="btn-od-secondary btn-compact">
          ← Back to Prescribe
        </Link>
      </div>

      {/* Patient Profile Strip */}
      {!patient && (
        <p style={{ padding: '24px', color: 'var(--muted)' }}>No patient selected. Tap a card on the Prescribe page first.</p>
      )}
      {patient && (
        <div className="od-card" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 24px', marginBottom: '20px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
            <div
              style={{
                width: '46px',
                height: '46px',
                borderRadius: '50%',
                backgroundColor: 'var(--brand-tint)',
                color: 'var(--brand-dark)',
                fontWeight: 700,
                fontSize: '16px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {patient.initials || 'MN'}
            </div>
            <div>
              <div style={{ fontSize: '18px', fontWeight: 700, color: 'var(--ink)' }}>
                {patient.full_name}
              </div>
              <div className="mono" style={{ fontSize: '13px', color: 'var(--muted)' }}>
                {patient.age_years} {patient.sex?.charAt(0).toUpperCase()} · P-{patient.patient_id || patient.id} · Card ID: {patient.card_id}
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {patient.conditions?.map((c, i) => (
              <span key={i} className="chip chip-neutral" style={{ margin: 0 }}>
                {c.name || c}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Time-Travel Control Strip */}
      <div className="od-card" style={{ marginBottom: '20px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
          <div>
            <span className="section-label" style={{ margin: 0 }}>TIME TRAVEL CONTROL</span>
            <div style={{ fontSize: '18px', fontWeight: 700, color: 'var(--brand-dark)', marginTop: '2px' }}>
              Viewing records as of: {selectedDate.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}
            </div>
          </div>

          <button
            type="button"
            className="btn-od-secondary btn-compact"
            onClick={handleResetToday}
            disabled={sliderDay === totalDays}
          >
            Reset to Today
          </button>
        </div>

        {/* Range Slider */}
        <input
          type="range"
          min="0"
          max={totalDays}
          value={sliderDay}
          onChange={(e) => setSliderDay(Number(e.target.value))}
          style={{
            width: '100%',
            height: '8px',
            accentColor: 'var(--brand)',
            cursor: 'ew-resize',
          }}
          aria-label="Time travel range slider"
        />

        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '12px', color: 'var(--muted)', marginTop: '6px' }}>
          <span>2 Years Ago ({twoYearsAgo.getFullYear()})</span>
          <span>1 Year Ago</span>
          <span>Today ({today.getFullYear()})</span>
        </div>
      </div>

      {/* Visual Timeline Section */}
      <div className="od-card" style={{ marginBottom: '24px' }}>
        <span className="section-label" style={{ marginBottom: '16px' }}>
          MEDICATION INTERVALS TIMELINE
        </span>

        {patient?.active_medications && patient.active_medications.length > 0 ? (
          <div style={{ position: 'relative', marginTop: '16px', paddingBottom: '8px' }}>
            {/* Vertical Marker for Selected Date */}
            <div
              style={{
                position: 'absolute',
                top: 0,
                bottom: 0,
                left: `${selectedDatePercent}%`,
                width: '2px',
                backgroundColor: 'var(--brand-dark)',
                zIndex: 5,
                pointerEvents: 'none',
              }}
            >
              <div
                style={{
                  position: 'absolute',
                  top: '-24px',
                  left: '-50%',
                  transform: 'translateX(-40%)',
                  backgroundColor: 'var(--brand-dark)',
                  color: '#FFFFFF',
                  fontSize: '10px',
                  fontWeight: 600,
                  padding: '2px 6px',
                  borderRadius: '4px',
                  whiteSpace: 'nowrap',
                }}
              >
                ▼ Selected Date
              </div>
            </div>

            {/* Rows of Medications */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              {patient.active_medications.map((med, idx) => {
                const left = dateToPercent(med.start_date);
                const right = med.end_date ? dateToPercent(med.end_date) : 100;
                const width = Math.max(right - left, 4);

                const isActiveOnDate =
                  new Date(med.start_date) <= selectedDate &&
                  (!med.end_date || new Date(med.end_date) >= selectedDate);

                return (
                  <div key={idx} style={{ display: 'grid', gridTemplateColumns: '180px 1fr', alignItems: 'center', gap: '16px' }}>
                    <div style={{ fontSize: '13px', fontWeight: 600, color: 'var(--ink)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {med.brand_name}
                    </div>

                    <div style={{ position: 'relative', height: '26px', backgroundColor: '#EEF2F6', borderRadius: '6px' }}>
                      <div
                        style={{
                          position: 'absolute',
                          left: `${left}%`,
                          width: `${width}%`,
                          top: 0,
                          bottom: 0,
                          borderRadius: '6px',
                          backgroundColor: isActiveOnDate ? 'var(--brand)' : '#CBD5E1',
                          background:
                            !med.end_date
                              ? isActiveOnDate
                                ? 'linear-gradient(to right, var(--brand), rgba(14, 159, 142, 0.45))'
                                : 'linear-gradient(to right, #CBD5E1, rgba(203, 213, 225, 0.3))'
                              : undefined,
                          transition: 'background-color 200ms ease',
                          display: 'flex',
                          alignItems: 'center',
                          paddingLeft: '8px',
                          color: isActiveOnDate ? '#FFFFFF' : 'var(--ink-soft)',
                          fontSize: '11px',
                          fontWeight: 600,
                          overflow: 'hidden',
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {isActiveOnDate ? 'Active' : 'Ended'}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ) : (
          <div style={{ padding: '24px', textAlign: 'center', color: 'var(--muted)' }}>
            No medication intervals to display.
          </div>
        )}
      </div>

      {/* Active on Selected Date Deck */}
      <div>
        <h3 style={{ fontSize: '18px', fontWeight: 700, marginBottom: '14px' }}>
          Active on {selectedDate.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}
        </h3>

        {isLoading ? (
          <div className="od-card" style={{ padding: '36px', textAlign: 'center', color: 'var(--muted)' }}>
            Loading historical medication snapshot...
          </div>
        ) : medications.length > 0 ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '16px' }}>
            {medications.map((m, idx) => (
              <div key={idx} className="od-card" style={{ margin: 0 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '8px' }}>
                  <div style={{ fontWeight: 700, fontSize: '16px', color: 'var(--ink)' }}>
                    {m.brand_name}
                  </div>
                  <span className="pill pill-ok">
                    Active
                  </span>
                </div>

                <div className="mono" style={{ fontSize: '13px', color: 'var(--muted)', marginBottom: '6px' }}>
                  {m.ingredients?.map((i) => `${i.name} ${i.strength_mg} mg`).join(' + ')}
                </div>

                <div style={{ fontSize: '13px', color: 'var(--ink-soft)' }}>
                  Intake: {m.dose_frequency || `${m.dose} mg - ${m.frequency}`}
                </div>

                <div style={{ fontSize: '11px', color: 'var(--muted)', marginTop: '10px' }}>
                  Started: {m.start_date} {m.end_date ? `· Ended: ${m.end_date}` : '· Ongoing'}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="od-card" style={{ padding: '36px', textAlign: 'center', color: 'var(--muted)' }}>
            <div style={{ fontWeight: 600, color: 'var(--ink)', marginBottom: '4px' }}>
              No medicines active on this date
            </div>
            <div style={{ fontSize: '13px' }}>
              The patient was taking no recorded prescriptions on {selectedDateStr}.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
