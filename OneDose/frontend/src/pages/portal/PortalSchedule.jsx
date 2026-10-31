// File: src/pages/portal/PortalSchedule.jsx - Today's schedule: morning, afternoon, night (suggested times)
import React from 'react';
import { getPortalSchedule } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState } from './portalBits.jsx';

const TITLES = { morning: 'Morning', afternoon: 'Afternoon', night: 'Night' };

export default function PortalSchedule() {
  const { data, error, loading, reload } = usePortal(getPortalSchedule);

  return (
    <div className="app-container">
      <PageHead title="Today's schedule" subtitle={data ? data.disclaimer : 'Suggested times for your prescribed medicines.'} />
      <LoadState loading={loading} error={error} onRetry={reload} />
      {data && (
        <div className="portal-grid-3">
          {data.slots.map((s) => (
            <div className="od-card" key={s.slot}>
              <span className="section-label">{TITLES[s.slot].toUpperCase()}</span>
              {s.items.length === 0 && <p className="portal-muted">Nothing scheduled.</p>}
              <ul className="portal-list">
                {s.items.map((it) => (
                  <li key={it.item_id}>
                    <div className="portal-row-top"><strong>{it.brand_name}</strong><span className="mono">{it.dose}</span></div>
                    {it.note && <div className="portal-muted">{it.note}</div>}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
