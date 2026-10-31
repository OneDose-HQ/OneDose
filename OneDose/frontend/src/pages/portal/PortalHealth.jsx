// File: src/pages/portal/PortalHealth.jsx - My health: allergies and conditions (read-only)
import React from 'react';
import { getPortalHealth } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState, AllergyChips, fmtDate } from './portalBits.jsx';

export default function PortalHealth() {
  const { data, error, loading, reload } = usePortal(getPortalHealth);

  return (
    <div className="app-container">
      <PageHead title="My health" subtitle="This is what your care team has recorded. To change it, tell your doctor." />
      <LoadState loading={loading} error={error} onRetry={reload} />
      {data && (
        <div className="portal-grid">
          <div className="od-card">
            <span className="section-label">ALLERGIES</span>
            <AllergyChips allergies={data.allergies} />
          </div>
          <div className="od-card">
            <span className="section-label">CONDITIONS</span>
            {data.conditions.length === 0 && <p className="portal-muted">No conditions are recorded.</p>}
            <ul className="portal-list">
              {data.conditions.map((c, i) => (
                <li key={i}>
                  <div className="portal-row-top"><strong>{c.name}</strong><span className="mono">{c.icd10 || ''}</span></div>
                  <div className="portal-muted">Since {fmtDate(c.valid_from)}</div>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </div>
  );
}
