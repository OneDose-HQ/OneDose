// File: src/components/AlertPanel.jsx - Displays clinical safety alerts, override modal dialog, and safer alternative medications
import React, { useState } from 'react';
import { validateOverrideReason } from '../validators.js';

// ---------------------------------------------------------------------
// INLINE SVGS FOR SAFETY CHECKS
// ---------------------------------------------------------------------
function IconInteraction({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M7 17 17 7" />
      <path d="m17 17-4-4" />
      <path d="M7 7l4 4" />
    </svg>
  );
}

function IconContraindication({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
      <line x1="2" y1="2" x2="22" y2="22" />
    </svg>
  );
}

function IconAllergy({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" />
      <line x1="12" y1="9" x2="12" y2="13" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  );
}

function IconDuplicate({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="9" cy="12" r="6" />
      <circle cx="15" cy="12" r="6" />
    </svg>
  );
}

function IconMaxDose({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 2v4" />
      <path d="m4.93 4.93 2.83 2.83" />
      <path d="M2 12h4" />
      <path d="M20 12h2" />
      <path d="m19.07 4.93-2.83 2.83" />
      <path d="M12 12l3-3" />
      <path d="M6 18a6 6 0 0 0 12 0" />
    </svg>
  );
}

function IconShieldCheck({ size = 32 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="var(--brand)" strokeWidth="1.8">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

export default function AlertPanel({
  alerts = [],
  alternatives = [],
  onOverride,
  onUseAlternative,
  readOnly = false,
}) {
  const [activeOverrideAlert, setActiveOverrideAlert] = useState(null);
  const [reasonText, setReasonText] = useState('');
  const [modalError, setModalError] = useState('');

  // Priority sort order: critical > major > moderate > minor
  const severityRank = { critical: 4, major: 3, moderate: 2, minor: 1 };
  const sortedAlerts = [...alerts].sort(
    (a, b) => (severityRank[b.severity] || 0) - (severityRank[a.severity] || 0)
  );

  const highestSeverity = sortedAlerts[0]?.severity || 'none';

  const handleOpenOverride = (alert) => {
    setActiveOverrideAlert(alert);
    setReasonText('');
    setModalError('');
  };

  const handleConfirmOverride = () => {
    const val = validateOverrideReason(reasonText);
    if (!val.valid) {
      setModalError(val.errors.reason);
      return;
    }
    if (onOverride && activeOverrideAlert) {
      onOverride(activeOverrideAlert.id, reasonText.trim());
    }
    setActiveOverrideAlert(null);
  };

  const getCheckIcon = (checkType) => {
    switch (checkType) {
      case 'interaction':
        return <IconInteraction />;
      case 'contraindication':
        return <IconContraindication />;
      case 'allergy':
        return <IconAllergy />;
      case 'duplicate':
        return <IconDuplicate />;
      case 'max_dose':
      case 'dose_limit':
        return <IconMaxDose />;
      default:
        return <IconInteraction />;
    }
  };

  const getSeverityStyles = (severity) => {
    switch (severity) {
      case 'critical':
        return { bg: 'var(--critical-tint)', color: 'var(--critical)', border: '#FCA5A5' };
      case 'major':
        return { bg: 'var(--major-tint)', color: 'var(--major)', border: '#F5CFAF' };
      case 'moderate':
        return { bg: 'var(--moderate-tint)', color: 'var(--moderate)', border: '#FDE68A' };
      case 'minor':
      default:
        return { bg: 'var(--minor-tint)', color: 'var(--minor)', border: '#BFDBFE' };
    }
  };

  return (
    <div className="od-card" aria-live="polite">
      {/* Header Row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
        <span className="section-label" style={{ margin: 0 }}>
          SAFETY ALERTS
        </span>
        {alerts.length > 0 && (
          <span className="mono" style={{ fontSize: '11px', color: 'var(--muted)' }}>
            {alerts.length} {alerts.length === 1 ? 'alert' : 'alerts'} · highest: {highestSeverity}
          </span>
        )}
      </div>

      {/* Alerts Content */}
      {alerts.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '36px 16px', color: 'var(--muted)' }}>
          <div style={{ marginBottom: '10px' }}>
            <IconShieldCheck />
          </div>
          <div style={{ fontWeight: 600, color: 'var(--ink)' }}>Run a check to see alerts.</div>
          <div style={{ fontSize: '12px', marginTop: '4px' }}>
            Enter brand, dose, and frequency to execute safety checks.
          </div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', marginBottom: '24px' }}>
          {sortedAlerts.map((alert) => {
            const styles = getSeverityStyles(alert.severity);
            const isOverridden = alert.status === 'overridden';

            if (isOverridden) {
              return (
                <div
                  key={alert.id}
                  style={{
                    backgroundColor: '#F1F5F9',
                    borderRadius: '12px',
                    padding: '12px 14px',
                    border: '1px solid var(--border)',
                    fontSize: '12px',
                    color: 'var(--ink-soft)',
                  }}
                >
                  <span style={{ fontWeight: 700, color: 'var(--ink)' }}>
                    ✓ Overridden:
                  </span>{' '}
                  {alert.override_reason}
                </div>
              );
            }

            return (
              <div
                key={alert.id}
                className="alert-card-slide"
                style={{
                  backgroundColor: styles.bg,
                  borderRadius: '12px',
                  padding: '14px 16px',
                  border: `1px solid ${styles.border}`,
                }}
              >
                {/* Badge and check type header */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                  <span className={`severity-badge ${alert.severity}`}>
                    {alert.severity.toUpperCase()}
                  </span>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', fontWeight: 700, fontSize: '13px', color: 'var(--ink)' }}>
                    {getCheckIcon(alert.check_type)}
                    {alert.display_type || (alert.check_type === 'contraindication' ? 'Drug-disease' : alert.check_type.charAt(0).toUpperCase() + alert.check_type.slice(1))}
                  </span>
                </div>

                {/* Ingredient Chips */}
                {alert.ingredients && alert.ingredients.length > 0 && (
                  <div style={{ marginBottom: '10px' }}>
                    {alert.ingredients.map((ingr, i) => (
                      <span key={i} className="chip chip-ingredient">
                        {ingr}
                      </span>
                    ))}
                  </div>
                )}

                {/* Explanation text */}
                <div style={{ fontSize: '13px', color: 'var(--ink)', lineHeight: 1.45, marginBottom: '8px' }}>
                  {alert.explanation}
                </div>

                {/* Source & Management text */}
                <div style={{ fontSize: '11px', color: 'var(--muted)', marginBottom: '12px', lineHeight: 1.4 }}>
                  Source: {alert.source || 'Curated'}
                  {alert.management && ` · Management: ${alert.management}`}
                </div>

                {/* Action button */}
                {!readOnly && (
                  <div>
                    <button
                      type="button"
                      className="btn-od-secondary btn-compact"
                      onClick={() => handleOpenOverride(alert)}
                    >
                      Override
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Safer Alternatives Section */}
      {alternatives.length > 0 && (
        <div style={{ borderTop: '1px solid var(--border)', paddingTop: '18px' }}>
          <span className="section-label" style={{ marginBottom: '12px' }}>
            SAFER ALTERNATIVES
          </span>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {alternatives.map((alt, idx) => {
              const isFirstLine = idx === 0 || alt.line_of_therapy === 'First line';
              return (
                <div
                  key={alt.brand_id || idx}
                  style={{
                    border: '1px solid var(--border)',
                    borderRadius: '12px',
                    padding: '14px',
                    backgroundColor: '#FFFFFF',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '4px' }}>
                    <div style={{ fontWeight: 700, fontSize: '15px', color: 'var(--ink)' }}>
                      {alt.brand_name}
                    </div>
                    <span
                      style={{
                        fontSize: '11px',
                        fontWeight: 600,
                        padding: '2px 8px',
                        borderRadius: 'var(--radius-pill)',
                        backgroundColor: isFirstLine ? 'var(--brand-tint)' : '#F1F5F9',
                        color: isFirstLine ? 'var(--brand-dark)' : 'var(--ink-soft)',
                      }}
                    >
                      {alt.line_of_therapy || 'Alternative'}
                    </span>
                  </div>

                  <div className="mono" style={{ fontSize: '12px', color: 'var(--muted)', marginBottom: '8px' }}>
                    {alt.ingredients?.join(' + ')}
                  </div>

                  <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--ok)', marginBottom: '12px' }}>
                    ✓ {alt.status_text || 'No conflicts with current medicines'}
                  </div>

                  {!readOnly && (
                    <button
                      type="button"
                      className={isFirstLine ? 'btn-od-primary btn-compact' : 'btn-od-secondary btn-compact'}
                      style={{ width: '100%' }}
                      onClick={() => onUseAlternative && onUseAlternative(alt)}
                    >
                      Use this instead
                    </button>
                  )}
                </div>
              );
            })}
          </div>

          <div style={{ fontSize: '11px', color: 'var(--muted)', marginTop: '12px', textAlign: 'center' }}>
            Suggestions from curated data. The doctor decides.
          </div>
        </div>
      )}

      {/* Override Modal (Plain React + CSS) */}
      {activeOverrideAlert && (
        <div
          className="od-modal-backdrop"
          onClick={() => setActiveOverrideAlert(null)}
          role="dialog"
          aria-modal="true"
          aria-labelledby="override-modal-title"
        >
          <div className="od-modal-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 id="override-modal-title" style={{ fontSize: '18px', fontWeight: 700, marginBottom: '6px' }}>
              Override Clinical Alert
            </h3>
            <p style={{ fontSize: '13px', color: 'var(--muted)', marginBottom: '16px' }}>
              Provide clinical justification for overriding this safety warning. All overrides are permanently recorded in the tamper-evident audit log.
            </p>

            <div style={{ marginBottom: '16px' }}>
              <label htmlFor="override-reason" className="form-label">
                Clinical Justification Reason (required)
              </label>
              <textarea
                id="override-reason"
                className={`form-control ${modalError ? 'is-invalid' : ''}`}
                rows={4}
                value={reasonText}
                onChange={(e) => {
                  setReasonText(e.target.value);
                  if (modalError) setModalError('');
                }}
                placeholder="e.g. Benefits outweigh acute gastrointestinal risks under concurrent PPI protection..."
                style={{ height: 'auto', resize: 'vertical' }}
              />
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '4px' }}>
                {modalError ? (
                  <span className="invalid-feedback" style={{ margin: 0 }}>
                    {modalError}
                  </span>
                ) : <span />}
                <span className="mono" style={{ fontSize: '11px', color: 'var(--muted)' }}>
                  {reasonText.trim().length} / 300 chars
                </span>
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                className="btn-od-secondary"
                onClick={() => setActiveOverrideAlert(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="btn-od-primary"
                onClick={handleConfirmOverride}
              >
                Confirm override
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
