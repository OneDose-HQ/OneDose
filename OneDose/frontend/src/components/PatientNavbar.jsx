// File: src/components/PatientNavbar.jsx - Top bar and sub-menu for a signed-in patient
import React, { useEffect } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { OneDoseLogoGlyph } from '../App.jsx';

const SECTIONS = {
  '/portal/medicines': ['My medicines', ''],
  '/portal/schedule': ['Schedule', ''],
  '/portal/ingredients': ['What is in them', 'portal-tile--blue'],
  '/portal/health': ['My health', 'portal-tile--green'],
  '/portal/symptoms': ['Symptom search', 'portal-tile--violet'],
  '/portal/self-reported': ['Medicines I take', 'portal-tile--slate'],
  '/portal/privacy': ['Privacy', 'portal-tile--navy'],
};

export default function PatientNavbar({ name, logout }) {
  const section = SECTIONS[useLocation().pathname];
  useEffect(() => {
    if (!section) return undefined;
    const cls = ['portal-section'];
    if (section[1]) cls.push(section[1]);
    document.body.classList.add(...cls);
    return () => document.body.classList.remove(...cls);
  }, [section]);
  return (
    <>
      <header className="navbar-od" role="banner">
        <div className="navbar-left">
          <NavLink to="/portal" className="brand-logo-link" aria-label="OneDose patient home">
            <OneDoseLogoGlyph size={28} />
            <span className="brand-name-text">OneDose</span>
          </NavLink>
        </div>
        <div className="navbar-right">
          <span className="pill-role">Patient</span>
          <span className="user-name">{name}</span>
          <button type="button" className="btn-logout" onClick={logout} aria-label="Log out of application">Log out</button>
        </div>
      </header>
        {section && (
          <nav className={`portal-backbar-wrap ${section[1]}`} aria-label="Patient menu">
            <div className="portal-backbar">
              <NavLink to="/portal" className="portal-back">&larr; Home</NavLink>
              <span className="portal-backbar-title">{section[0]}</span>
            </div>
          </nav>
        )}
    </>
  );
}
