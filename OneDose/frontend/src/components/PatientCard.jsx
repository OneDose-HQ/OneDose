// File: src/components/PatientCard.jsx - Displays patient demographic, allergy, condition, and active medication profile
import React from 'react';
import { Link } from 'react-router-dom';

export default function PatientCard({ patient }) {
  if (!patient) {
    return (
      <div className="od-card" style={{ textAlign: 'center', padding: '36px 20px', color: 'var(--muted)' }}>
        <div
          style={{
            width: '48px',
            height: '48px',
            borderRadius: '50%',
            backgroundColor: 'var(--bg)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            margin: '0 auto 12px',
          }}
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--ink-soft)" strokeWidth="1.8">
            <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
            <circle cx="12" cy="7" r="4" />
          </svg>
        </div>
        <div style={{ fontWeight: 600, color: 'var(--ink)', marginBottom: '4px' }}>No patient loaded</div>
        <div style={{ fontSize: '13px' }}>Tap a card or select a demo patient above to view records.</div>
      </div>
    );
  }

  const {
    id,
    patient_id,
    full_name,
    age_years,
    sex,
    initials,
    has_active_consent,
    consent_status,
    allergies = [],
    conditions = [],
    active_medications = [],
  } = patient;

  const displayId = id || patient_id;
  const sexCode = sex ? sex.charAt(0).toUpperCase() : '';  // the pharmacist's masked view sends no sex
  const consentText = consent_status || (has_active_consent ? 'Consent active' : 'No active consent');

  return (
    <div className="od-card">
      {/* Patient Header: Avatar, Name, Demographic Subtitle */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '14px' }}>
        <div
          style={{
            width: '48px',
            height: '48px',
            borderRadius: '50%',
            backgroundColor: 'var(--brand-tint)',
            color: 'var(--brand-dark)',
            fontWeight: 700,
            fontSize: '16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          {initials || full_name?.split(' ').map((n) => n[0]).join('').slice(0, 2) || 'PT'}
        </div>
        <div>
          <div style={{ fontSize: '16px', fontWeight: 700, color: 'var(--ink)', lineHeight: 1.2 }}>
            {full_name}
          </div>
          <div className="mono" style={{ fontSize: '12px', color: 'var(--ink-soft)', marginTop: '2px' }}>
            {age_years}{sexCode ? ` ${sexCode}` : ''} · P-{displayId}
          </div>
        </div>
      </div>

      {/* Consent Pill */}
      <div style={{ marginBottom: '18px' }}>
        <span className={`pill ${has_active_consent ? 'pill-ok' : 'pill-expired'}`}>
          <span style={{ fontSize: '10px' }}>●</span>
          {consentText}
        </span>
      </div>

      {/* Allergies Section */}
      <div style={{ marginBottom: '16px' }}>
        <span className="section-label">ALLERGIES</span>
        {allergies.length > 0 ? (
          <div>
            {allergies.map((allergy, idx) => (
              <span key={idx} className="chip chip-danger">
                {typeof allergy === 'string' ? allergy : allergy.name}
              </span>
            ))}
          </div>
        ) : (
          <span style={{ fontSize: '13px', color: 'var(--muted)' }}>No recorded allergies</span>
        )}
      </div>

      {/* Conditions Section */}
      <div style={{ marginBottom: '18px' }}>
        <span className="section-label">CONDITIONS</span>
        {conditions.length > 0 ? (
          <div>
            {conditions.map((cond, idx) => (
              <span key={idx} className="chip chip-neutral">
                {typeof cond === 'string' ? cond : cond.name}
              </span>
            ))}
          </div>
        ) : (
          <span style={{ fontSize: '13px', color: 'var(--muted)' }}>No chronic conditions recorded</span>
        )}
      </div>

      {/* Active Medicines Section */}
      <div style={{ marginBottom: '16px' }}>
        <span className="section-label">ACTIVE MEDICINES</span>
        {active_medications.length > 0 ? (
          <div>
            {active_medications.map((med, idx) => (
              <div
                key={idx}
                style={{
                  padding: '9px 0',
                  borderBottom: idx < active_medications.length - 1 ? '1px solid var(--border)' : 'none',
                }}
              >
                <div style={{ fontWeight: 700, fontSize: '14px', color: 'var(--ink)' }}>
                  {med.brand_name}
                </div>
                <div className="mono" style={{ fontSize: '12px', color: 'var(--muted)' }}>
                  {med.ingredients?.map((i) => `${i.name} ${i.strength_mg} mg`).join(' + ') || med.ingredient_text}
                </div>
                <div style={{ fontSize: '12px', color: 'var(--ink-soft)' }}>
                  {med.dose_frequency || `${med.dose} mg - ${med.frequency}`}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <span style={{ fontSize: '13px', color: 'var(--muted)' }}>No current active medications</span>
        )}
      </div>

      {/* View History Link */}
      <div style={{ borderTop: '1px solid var(--border)', paddingTop: '12px' }}>
        <Link
          to={`/history/${displayId}`}
          style={{ fontSize: '13px', fontWeight: 600, color: 'var(--brand)', textDecoration: 'none' }}
        >
          View history →
        </Link>
      </div>
    </div>
  );
}
