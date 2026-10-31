// File: src/pages/portal/PortalSymptoms.jsx - Symptom search: past medicines for a symptom, with dates, dose and prescriber
import React, { useState } from 'react';
import { searchPortalSymptom } from '../../api.js';
import { PageHead, fmtDate } from './portalBits.jsx';

export default function PortalSymptoms() {
  const [q, setQ] = useState('');
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const search = async (e) => {
    e.preventDefault();
    if (q.trim().length < 2) {
      setError('Type at least 2 letters, for example: fever');
      return;
    }
    setLoading(true);
    setError('');
    try {
      setRows(await searchPortalSymptom(q.trim()));
    } catch (err) {
      setRows(null);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="app-container">
      <PageHead title="Search by symptom" subtitle="See which medicines you were prescribed in the past for something like fever." />
      <form className="od-card portal-inline" onSubmit={search}>
        <label htmlFor="symptom-q" className="form-label" style={{ margin: 0 }}>Symptom</label>
        <input id="symptom-q" className="form-control" style={{ maxWidth: '260px' }} value={q} maxLength={60}
               placeholder="fever" onChange={(e) => setQ(e.target.value)} />
        <button type="submit" className="btn-od-primary" disabled={loading}>{loading ? 'Searching...' : 'Search'}</button>
      </form>
      {error && <div className="od-card portal-error" role="alert">{error}</div>}
      {rows && (
        <div className="od-card" style={{ overflowX: 'auto' }}>
          {rows.length === 0 ? <p className="portal-muted">No prescribed medicine in your record is listed for that symptom.</p> : (
            <table className="portal-table">
              <thead><tr><th>Medicine</th><th>Used for</th><th>Dates</th><th>Dose</th><th>Prescribed by</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.item_id}>
                    <td><strong>{r.brand_name}</strong><div className="portal-muted">{r.ingredients}</div></td>
                    <td>{r.indication}</td>
                    <td>{fmtDate(r.start_date)} to {r.end_date ? fmtDate(r.end_date) : 'ongoing'}</td>
                    <td>{r.dose}</td>
                    <td>{r.prescriber}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
