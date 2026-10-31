// File: src/pages/portal/PortalPrivacy.jsx - Privacy: give or withdraw consent, and see who viewed my record
import React, { useState } from 'react';
import { getPortalConsent, getPortalAccessLog, revokePortalConsent, grantPortalConsent } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState, fmtDateTime } from './portalBits.jsx';

export default function PortalPrivacy() {
  const consent = usePortal(getPortalConsent);
  const log = usePortal(getPortalAccessLog);
  const [days, setDays] = useState(365);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  const act = async (fn, okMessage) => {
    setBusy(true);
    setMsg('');
    try {
      await fn();
      setMsg(okMessage);
      consent.reload();
      log.reload();
    } catch (e) {
      setMsg(e.message);
    } finally {
      setBusy(false);
    }
  };

  const withdraw = () => {
    const ok = window.confirm('Withdraw access? Your care team will not be able to open your record until you allow it again.');
    if (ok) act(revokePortalConsent, 'Access withdrawn.');
  };

  const active = consent.data && consent.data.active;

  return (
    <div className="app-container">
      <PageHead title="Privacy" subtitle="You decide whether your care team can open your record." />
      <LoadState loading={consent.loading} error={consent.error} onRetry={consent.reload} />
      {consent.data && (
        <div className="od-card">
          <span className="section-label">CARE TEAM ACCESS</span>
          <p><span className={active ? 'pill pill-ok' : 'pill pill-expired'}>{active ? 'On' : 'Off'}</span></p>
          <p>{consent.data.status}</p>
          {active ? (
            <button type="button" className="btn-od-secondary" disabled={busy} onClick={withdraw}>Withdraw access</button>
          ) : (
            <div className="portal-inline">
              <label htmlFor="consent-days" className="form-label" style={{ margin: 0 }}>Allow access for</label>
              <select id="consent-days" className="form-select" style={{ maxWidth: '160px' }} value={days}
                      onChange={(e) => setDays(Number(e.target.value))}>
                <option value={30}>30 days</option>
                <option value={90}>90 days</option>
                <option value={365}>1 year</option>
              </select>
              <button type="button" className="btn-od-primary" disabled={busy}
                      onClick={() => act(() => grantPortalConsent(days), 'Access allowed.')}>Allow access</button>
            </div>
          )}
          {msg && <p role="status" className="portal-muted" style={{ marginTop: '10px' }}>{msg}</p>}
        </div>
      )}

      <span className="section-label">WHO VIEWED MY RECORD</span>
      <LoadState loading={log.loading} error={log.error} onRetry={log.reload} />
      {log.data && (
        <div className="od-card" style={{ overflowX: 'auto' }}>
          {log.data.length === 0 ? <p className="portal-muted">Nobody has opened your record yet.</p> : (
            <table className="portal-table">
              <thead><tr><th>When</th><th>Who</th><th>What</th></tr></thead>
              <tbody>
                {log.data.map((r, i) => (
                  <tr key={i}>
                    <td>{fmtDateTime(r.occurred_at)}</td>
                    <td>{r.who} <span className="portal-muted">({r.staff_role})</span></td>
                    <td>{r.what}</td>
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
