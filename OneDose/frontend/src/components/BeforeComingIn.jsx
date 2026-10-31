// File: src/components/BeforeComingIn.jsx - "Before coming in": medicines the patient reported themselves (unverified)
// Shown to the clinician under the patient card. These are NOT part of the prescription safety checks.
import React, { useEffect, useState } from 'react';
import { getBeforeComingIn } from '../api.js';

export default function BeforeComingIn({ patientId }) {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!patientId) return undefined;
    let alive = true;
    setRows(null);
    setError('');
    getBeforeComingIn(patientId)
      .then((r) => { if (alive) setRows(r); })
      .catch((e) => { if (alive) setError(e.message); });
    return () => { alive = false; };
  }, [patientId]);

  return (
    <div className="od-card">
        <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
          style={{ width: '100%', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'none', border: 'none', padding: 0, cursor: 'pointer', textAlign: 'left', color: 'inherit', font: 'inherit', letterSpacing: 'inherit', textTransform: 'inherit' }}>
          <span className="section-label" style={{ margin: 0 }}>BEFORE COMING IN ({rows ? rows.length : '...'})</span>
          <span aria-hidden="true">{open ? '\u25B2' : '\u25BC'}</span>
        </button>
        {open && (<>
      <p className="portal-muted" style={{ marginTop: 0 }}>Reported by the patient. Unverified, not part of the safety checks.</p>
      {error && <div className="portal-muted" role="alert">{error}</div>}
      {!rows && !error && <div className="portal-muted">Loading...</div>}
      {rows && rows.length === 0 && <div className="portal-muted">Nothing reported.</div>}
      {rows && (
        <ul className="portal-list">
          {rows.map((m) => (
            <li key={m.report_id} style={{ opacity: m.active ? 1 : 0.6 }}>
              <div className="portal-row-top">
                <strong>{m.medicine}{m.strength ? ` ${m.strength}` : ''}</strong>
                <span className="pill pill-tag">Unverified</span>
              </div>
              <div className="portal-muted">
                {m.times_per_day ? `${m.times_per_day} time(s) a day` : 'Frequency not given'}{m.active ? '' : ' (stopped)'}
              </div>
              {m.note && <div className="portal-muted">{m.note}</div>}
              <div className={`portal-check portal-check-${m.check.state}`}>{m.check.text}</div>
            </li>
          ))}
        </ul>
      )}
        </>)}
    </div>
  );
}
