// File: src/pages/portal/portalBits.jsx - Small pieces shared by the patient portal pages
import React from 'react';

export function fmtDate(d) {
  if (!d) return '';
  const text = String(d);
  const date = new Date(text.length === 10 ? `${text}T00:00:00` : text);
  return date.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

export function fmtDateTime(d) {
  if (!d) return '';
  return new Date(d).toLocaleString('en-IN', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function todayIso() {
  return new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD in the local time zone
}

export function PageHead({ title, subtitle }) {
  return (
    <>
      <h1 className="page-title">{title}</h1>
      {subtitle && <p className="page-subtitle">{subtitle}</p>}
    </>
  );
}

export function LoadState({ loading, error, onRetry }) {
  if (loading) return <div className="od-card" role="status">Loading...</div>;
  if (error) {
    return (
      <div className="od-card portal-error" role="alert">
        <span>{error}</span>{' '}
        {onRetry && <button type="button" className="btn-od-secondary btn-compact" onClick={onRetry}>Try again</button>}
      </div>
    );
  }
  return null;
}

export function MedList({ meds, empty }) {
  if (!meds || meds.length === 0) return <p className="portal-muted">{empty}</p>;
  return (
    <ul className="portal-list">
      {meds.map((m) => (
        <li key={m.prescription_item_id}>
          <div className="portal-row-top">
            <strong>{m.brand_name}</strong>
            <span className="mono">{m.dose_frequency}</span>
          </div>
          <div className="portal-muted">{m.ingredients.map((i) => `${i.name} ${i.strength_mg} mg`).join(' + ')}</div>
          <div className="portal-muted">
            Started {fmtDate(m.start_date)}{m.end_date ? `, until ${fmtDate(m.end_date)}` : ''}
          </div>
        </li>
      ))}
    </ul>
  );
}

export function AllergyChips({ allergies }) {
  if (!allergies || allergies.length === 0) return <p className="portal-muted">No allergies are recorded.</p>;
  return (
    <div className="portal-chips">
      {allergies.map((a, i) => (
        <span key={i} className="chip chip-danger">{a.name}{a.reaction ? ` (${a.reaction})` : ''}</span>
      ))}
    </div>
  );
}
