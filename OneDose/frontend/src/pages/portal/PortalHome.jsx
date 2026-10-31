// File: src/pages/portal/PortalHome.jsx - Patient home: today's medicines, allergies and consent status
import React from 'react';
import { Link } from 'react-router-dom';
import { getPortalHome } from '../../api.js';
import usePortal from './usePortal.js';
import { PageHead, LoadState, MedList, AllergyChips } from './portalBits.jsx';

const SVG = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': 'true' };

const TILES = [
  { to: '/portal/medicines', title: 'My medicines', desc: "What you are prescribed, and today's schedule", tone: '',
    icon: (<svg {...SVG}><rect x="3" y="9" width="18" height="6" rx="3" transform="rotate(-45 12 12)" /><path d="M9.5 9.5l5 5" /></svg>) },
  { to: '/portal/ingredients', title: 'What is in them', desc: 'The ingredients of each medicine', tone: 'portal-tile--blue',
    icon: (<svg {...SVG}><path d="M9 3h6M10 3v6l-5 9a2 2 0 0 0 1.8 3h10.4A2 2 0 0 0 19 18l-5-9V3" /></svg>) },
  { to: '/portal/health', title: 'My health', desc: 'Allergies and your health record', tone: 'portal-tile--green',
    icon: (<svg {...SVG}><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z" /></svg>) },
  { to: '/portal/symptoms', title: 'Symptom search', desc: 'Find which of your medicines may help', tone: 'portal-tile--violet',
    icon: (<svg {...SVG}><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /></svg>) },
  { to: '/portal/self-reported', title: 'Medicines I take', desc: 'Add medicines you buy yourself', tone: 'portal-tile--slate',
    icon: (<svg {...SVG}><rect x="5" y="4" width="14" height="17" rx="2" /><path d="M9 4h6v3H9zM9 12h6M9 16h4" /></svg>) },
  { to: '/portal/privacy', title: 'Privacy', desc: 'Who can see your record', tone: 'portal-tile--navy',
    icon: (<svg {...SVG}><path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z" /><path d="M9 12l2 2 4-4" /></svg>) },
];

export default function PortalHome() {
  const { data, error, loading, reload } = usePortal(getPortalHome);

  return (
    <div className="app-container">
      <PageHead
        title={data ? `Hello, ${data.name}` : 'My OneDose'}
        subtitle="Your medicines, allergies and privacy in one place. Use this to understand your care, not to change it."
      />
        <nav className="portal-tiles" aria-label="Portal sections">
          {TILES.map((t) => (
            <Link key={t.to} to={t.to} className={`portal-tile ${t.tone}`}>
              <span className="portal-tile-icon">{t.icon}</span>
              <span className="portal-tile-title">{t.title}</span>
              <span className="portal-tile-desc">{t.desc}</span>
            </Link>
          ))}
        </nav>
      <LoadState loading={loading} error={error} onRetry={reload} />
      {data && (
        <div className="portal-grid">
          <div className="od-card portal-tinted">
            <span className="section-label">TODAY'S MEDICINES</span>
            <MedList meds={data.medications} empty="No prescribed medicines are active today." />
            <Link className="portal-link" to="/portal/schedule">See today's schedule</Link>
          </div>
          <div>
            <div className="od-card portal-tinted portal-tile--green">
              <span className="section-label">ALLERGIES</span>
              <AllergyChips allergies={data.allergies} />
              <Link className="portal-link" to="/portal/health">See my health record</Link>
            </div>
            <div className="od-card portal-tinted portal-tile--navy">
              <span className="section-label">PRIVACY</span>
              <p>
                <span className={data.consent.active ? 'pill pill-ok' : 'pill pill-expired'}>
                  {data.consent.active ? 'Care team access on' : 'Care team access off'}
                </span>
              </p>
              <p className="portal-muted">{data.consent.status}</p>
              <Link className="portal-link" to="/portal/privacy">Manage privacy</Link>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
