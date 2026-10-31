// File: src/pages/portal/PortalIngredients.jsx - Plain sentence for each active ingredient (from the indication data)
import React from 'react';
import { getPortalIngredients } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState } from './portalBits.jsx';

export default function PortalIngredients() {
  const { data, error, loading, reload } = usePortal(getPortalIngredients);

  return (
    <div className="app-container">
      <PageHead
        title="What is in my medicines"
        subtitle="Each tablet contains one or more active ingredients. This is general information, not advice for you."
      />
      <LoadState loading={loading} error={error} onRetry={reload} />
      {data && data.length === 0 && <div className="od-card portal-muted">You have no active prescribed medicines.</div>}
      {data && data.map((e) => (
        <div className="od-card" key={e.ingredient}>
          <strong style={{ textTransform: 'capitalize' }}>{e.ingredient}</strong>
          <p style={{ margin: '6px 0' }}>{e.sentence}</p>
          <div className="portal-muted">Found in: {e.brands.join(', ')}</div>
        </div>
      ))}
    </div>
  );
}
