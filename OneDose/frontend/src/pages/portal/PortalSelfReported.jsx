// File: src/pages/portal/PortalSelfReported.jsx - Medicines I take myself (store-bought). Shown to the doctor as unverified.
import React, { useEffect, useState } from 'react';
import { getSelfReported, addSelfReported, stopSelfReported, searchPortalBrands } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState, fmtDate } from './portalBits.jsx';

const FREQUENCIES = [['OD', 'Once a day'], ['BD', 'Twice a day'], ['TDS', 'Three times a day'], ['QID', 'Four times a day'], ['SOS', 'Only when needed']];

export default function PortalSelfReported() {
  const list = usePortal(getSelfReported);
  const [q, setQ] = useState('');
  const [results, setResults] = useState([]);
  const [picked, setPicked] = useState(null);
  const [typed, setTyped] = useState('');
  const [freq, setFreq] = useState('OD');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  useEffect(() => {
    if (picked || q.trim().length < 2) { setResults([]); return undefined; }
    const timer = setTimeout(() => {
      searchPortalBrands(q.trim()).then(setResults).catch(() => setResults([]));
    }, 300);
    return () => clearTimeout(timer);
  }, [q, picked]);

  const submit = async (e) => {
    e.preventDefault();
    const name = typed.trim();
    if (!picked && name.length < 2) { setMsg('Pick a medicine from the list, or type its name.'); return; }
    setBusy(true);
    setMsg('');
    try {
      await addSelfReported({
        brand_id: picked ? picked.brand_id : null,
        free_text_name: picked ? null : name,
        frequency: freq,
        note: note.trim() || null,
      });
      setQ(''); setPicked(null); setTyped(''); setNote(''); setFreq('OD');
      setMsg('Added. Your doctor will see it marked as unverified.');
      list.reload();
    } catch (err) {
      setMsg(err.message);
    } finally {
      setBusy(false);
    }
  };

  const stop = async (id) => {
    try { await stopSelfReported(id); list.reload(); } catch (err) { setMsg(err.message); }
  };

  return (
    <div className="app-container">
      <PageHead title="Medicines I take myself"
                subtitle="Add tablets you bought yourself. Your doctor sees them before your visit, marked as unverified." />
      <form className="od-card" onSubmit={submit}>
        <span className="section-label">ADD A MEDICINE</span>
        {picked ? (
          <p><strong>{picked.brand_name}</strong> <span className="portal-muted">{picked.ingredients.join(' + ')}</span>{' '}
            <button type="button" className="btn-od-secondary btn-compact" onClick={() => setPicked(null)}>Change</button></p>
        ) : (
          <>
            <label htmlFor="srm-search" className="form-label">Search the medicine list</label>
            <input id="srm-search" className="form-control" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Dolo, Crocin ..." />
            {results.length > 0 && (
              <ul className="portal-list portal-results">
                {results.map((r) => (
                  <li key={r.brand_id}>
                    <button type="button" className="portal-pick" onClick={() => setPicked(r)}>
                      <strong>{r.brand_name}</strong> <span className="portal-muted">{r.ingredients.join(' + ')}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <label htmlFor="srm-typed" className="form-label" style={{ marginTop: '12px' }}>Not in the list? Type its name</label>
            <input id="srm-typed" className="form-control" value={typed} maxLength={80} onChange={(e) => setTyped(e.target.value)} />
            <div className="portal-muted">Typed names cannot be checked for allergies.</div>
          </>
        )}
        <label htmlFor="srm-freq" className="form-label" style={{ marginTop: '12px' }}>How often</label>
        <select id="srm-freq" className="form-select" value={freq} onChange={(e) => setFreq(e.target.value)}>
          {FREQUENCIES.map(([code, label]) => <option key={code} value={code}>{label}</option>)}
        </select>
        <label htmlFor="srm-note" className="form-label" style={{ marginTop: '12px' }}>Note (optional)</label>
        <input id="srm-note" className="form-control" value={note} maxLength={300} onChange={(e) => setNote(e.target.value)} />
        <div style={{ marginTop: '14px' }}>
          <button type="submit" className="btn-od-primary" disabled={busy}>{busy ? 'Saving...' : 'Add medicine'}</button>
        </div>
        {msg && <p role="status" className="portal-muted" style={{ marginTop: '10px' }}>{msg}</p>}
      </form>

      <LoadState loading={list.loading} error={list.error} onRetry={list.reload} />
      {list.data && list.data.length === 0 && <div className="od-card portal-muted">You have not added any medicines yet.</div>}
      {list.data && list.data.map((m) => (
        <div className="od-card" key={m.report_id} style={{ opacity: m.active ? 1 : 0.65 }}>
          <div className="portal-row-top">
            <strong>{m.medicine}{m.strength ? ` ${m.strength}` : ''}</strong>
            <span className="pill pill-tag">Unverified</span>
          </div>
          <div className="portal-muted">
            {m.times_per_day ? `${m.times_per_day} time(s) a day, ` : ''}since {fmtDate(m.started_on)}
            {m.stopped_on ? `, stopped ${fmtDate(m.stopped_on)}` : ''}
          </div>
          {m.note && <div className="portal-muted">{m.note}</div>}
          <div className={`portal-check portal-check-${m.check.state}`}>{m.check.text}</div>
          {m.active && <button type="button" className="btn-od-secondary btn-compact" style={{ marginTop: '10px' }}
                               onClick={() => stop(m.report_id)}>I stopped taking this</button>}
        </div>
      ))}
    </div>
  );
}
