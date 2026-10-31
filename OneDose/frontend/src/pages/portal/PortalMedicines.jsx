// File: src/pages/portal/PortalMedicines.jsx - My medicines with a date picker for past days
import React, { useState } from 'react';
import { getPortalMedications } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState, MedList, fmtDate, todayIso } from './portalBits.jsx';

export default function PortalMedicines() {
  const [day, setDay] = useState(todayIso());
  const { data, error, loading, reload } = usePortal(() => getPortalMedications(day || undefined), [day]);

  return (
    <div className="app-container">
      <PageHead title="My medicines" subtitle="Pick a day to see what was prescribed for you on that day." />
      <div className="od-card">
        <label htmlFor="portal-day" className="form-label">Day</label>
        <input
          id="portal-day"
          type="date"
          className="form-control"
          style={{ maxWidth: '220px' }}
          value={day}
          max={todayIso()}
          onChange={(e) => setDay(e.target.value)}
        />
      </div>
      <LoadState loading={loading} error={error} onRetry={reload} />
      {data && !loading && (
        <div className="od-card">
          <span className="section-label">TAKING ON {fmtDate(data.as_of).toUpperCase()}</span>
          <MedList meds={data.medications} empty="No prescribed medicines were active on this day." />
        </div>
      )}
    </div>
  );
}
