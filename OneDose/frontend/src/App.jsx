// File: src/App.jsx - Root layout, navigation, global authentication context, and toast notifications
import React, { createContext, useContext, useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate, NavLink, useLocation, useNavigate } from 'react-router-dom';
import Login from './pages/Login.jsx';
import Prescribe from './pages/Prescribe.jsx';
import PatientHistory from './pages/PatientHistory.jsx';
import Analytics from './pages/Analytics.jsx';
import PatientNavbar from './components/PatientNavbar.jsx';
import PortalHome from './pages/portal/PortalHome.jsx';
import PortalMedicines from './pages/portal/PortalMedicines.jsx';
import PortalSchedule from './pages/portal/PortalSchedule.jsx';
import PortalIngredients from './pages/portal/PortalIngredients.jsx';
import PortalHealth from './pages/portal/PortalHealth.jsx';
import PortalSymptoms from './pages/portal/PortalSymptoms.jsx';
import PortalSelfReported from './pages/portal/PortalSelfReported.jsx';
import PortalPrivacy from './pages/portal/PortalPrivacy.jsx';

// ---------------------------------------------------------------------
// CONTEXT DEFINITION
// ---------------------------------------------------------------------
export const AppContext = createContext(null);

export function useApp() {
  return useContext(AppContext);
}

// ---------------------------------------------------------------------
// INLINE SVG BRAND LOGO (Matching Image 2 and Image 3)
// ---------------------------------------------------------------------
export function OneDoseLogoGlyph({ size = 26 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      style={{ display: 'inline-block', verticalAlign: 'middle' }}
      aria-hidden="true"
    >
      {/* Light circle background */}
      <circle cx="50" cy="50" r="46" fill="#DDE4E9" />
      
      {/* Left green capsule tilted ~30 deg */}
      <g transform="rotate(-30 40 55)">
        <rect x="22" y="38" width="44" height="24" rx="12" fill="#0E7756" stroke="#FFFFFF" strokeWidth="2.5" />
        {/* Top/front cap in brighter green */}
        <path d="M 22 50 A 12 12 0 0 1 44 38 L 44 62 A 12 12 0 0 1 22 50 Z" fill="#1DAA74" />
        {/* Gloss highlight stripe */}
        <line x1="28" y1="42" x2="38" y2="42" stroke="#FFFFFF" strokeWidth="2" strokeLinecap="round" opacity="0.8" />
        {/* Center divider seam */}
        <line x1="44" y1="38" x2="44" y2="62" stroke="#FFFFFF" strokeWidth="2" />
      </g>

      {/* Right vertical navy-to-teal capsule */}
      <g transform="rotate(8 68 45)">
        <rect x="54" y="16" width="26" height="58" rx="13" fill="#0B1F33" stroke="#FFFFFF" strokeWidth="2.5" />
        {/* Lower cap in vibrant teal */}
        <path d="M 54 45 L 80 45 L 80 61 A 13 13 0 0 1 54 61 Z" fill="#0E9F8E" />
        {/* Gloss highlight stripe */}
        <line x1="60" y1="22" x2="60" y2="40" stroke="#FFFFFF" strokeWidth="2.5" strokeLinecap="round" opacity="0.8" />
        {/* Center divider seam */}
        <line x1="54" y1="45" x2="80" y2="45" stroke="#FFFFFF" strokeWidth="2" />
      </g>
    </svg>
  );
}

// ---------------------------------------------------------------------
// TOP NAVBAR COMPONENT (Matching Image 3)
// ---------------------------------------------------------------------
function Navbar() {
  const { auth, logout } = useApp();
  const location = useLocation();

  if (location.pathname === '/login') {
    return null;
  }

  if (auth?.user?.role === 'patient') {
    return <PatientNavbar name={auth.user.name} logout={logout} />;
  }

  const role = auth?.user?.role || 'clinician';
  const name = auth?.user?.name || 'Clinician';
  const roleDisplay = role.charAt(0).toUpperCase() + role.slice(1);
  const isPharmacist = role === 'pharmacist';
  const canViewAnalytics = role === 'admin' || role === 'clinician';

  return (
    <header className="navbar-od" role="banner">
      <div className="navbar-left">
        <NavLink to="/prescribe" className="brand-logo-link" aria-label="OneDose Home">
          <OneDoseLogoGlyph size={28} />
          <span className="brand-name-text">OneDose</span>
        </NavLink>

        <nav aria-label="Main Navigation">
          <ul className="nav-links">
            <li>
              <NavLink
                to="/prescribe"
                className={({ isActive }) => `nav-link-item ${isActive ? 'active' : ''}`}
              >
                Prescribe
              </NavLink>
            </li>
            <li>
              <NavLink
                to="/history"
                className={({ isActive }) => `nav-link-item ${isActive ? 'active' : ''}`}
              >
                History
              </NavLink>
            </li>
            {canViewAnalytics && (
              <li>
                <NavLink
                  to="/analytics"
                  className={({ isActive }) => `nav-link-item ${isActive ? 'active' : ''}`}
                >
                  Analytics
                </NavLink>
              </li>
            )}
          </ul>
        </nav>
      </div>

      <div className="navbar-right">
        {isPharmacist && (
          <span className="badge bg-warning text-dark px-2 py-1 rounded-pill" style={{ fontSize: '11px', fontWeight: 600 }}>
            Read-only view
          </span>
        )}
        <span className="pill-role">{roleDisplay}</span>
        <span className="user-name">{name}</span>
        <button
          type="button"
          className="btn-logout"
          onClick={logout}
          aria-label="Log out of application"
        >
          Log out
        </button>
      </div>
    </header>
  );
}

// ---------------------------------------------------------------------
// PROTECTED ROUTE WRAPPER
// ---------------------------------------------------------------------
const STAFF = ['clinician', 'pharmacist', 'admin'];
const PORTAL_PAGES = [
  ['/portal', PortalHome],
  ['/portal/medicines', PortalMedicines],
  ['/portal/schedule', PortalSchedule],
  ['/portal/ingredients', PortalIngredients],
  ['/portal/health', PortalHealth],
  ['/portal/symptoms', PortalSymptoms],
  ['/portal/self-reported', PortalSelfReported],
  ['/portal/privacy', PortalPrivacy],
];

function homeFor(role) {
  return role === 'patient' ? '/portal' : '/prescribe';
}

// roles: optional list of roles allowed on this page; anyone else is sent to their own home page
function ProtectedRoute({ children, roles }) {
  const { auth } = useApp();
  if (!auth?.token) {
    return <Navigate to="/login" replace />;
  }
  const role = auth?.user?.role;
  if (roles && !roles.includes(role)) {
    return <Navigate to={homeFor(role)} replace />;
  }
  return children;
}

function HomeRedirect() {
  const { auth } = useApp();
  return <Navigate to={auth?.token ? homeFor(auth?.user?.role) : '/login'} replace />;
}

// ---------------------------------------------------------------------
// MAIN APP COMPONENT
// ---------------------------------------------------------------------
export default function App() {
  const [auth, setAuth] = useState(() => {
    try {
      const stored = localStorage.getItem('onedose_auth');
      return stored ? JSON.parse(stored) : null;
    } catch {
      return null;
    }
  });

  const [selectedPatient, setSelectedPatient] = useState(null);
  const [toasts, setToasts] = useState([]);

  const addToast = (message, type = 'info') => {
    const id = Date.now() + Math.random().toString(36).substring(2, 6);
    setToasts((prev) => [...prev, { id, message, type }]);
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, 3800);
  };

  const loginAuth = (authData) => {
    setAuth(authData);
    localStorage.setItem('onedose_auth', JSON.stringify(authData));
  };

  const logout = () => {
    setAuth(null);
    setSelectedPatient(null);
    localStorage.removeItem('onedose_auth');
  };

  return (
    <AppContext.Provider
      value={{
        auth,
        loginAuth,
        logout,
        selectedPatient,
        setSelectedPatient,
        addToast,
      }}
    >
      <BrowserRouter>
        <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
          <Navbar />

          <main style={{ flex: '1 0 auto' }}>
            <Routes>
              <Route path="/login" element={<Login />} />
              <Route
                path="/prescribe"
                element={
                  <ProtectedRoute roles={STAFF}>
                    <Prescribe />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/history/:patientId?"
                element={
                  <ProtectedRoute roles={STAFF}>
                    <PatientHistory />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/analytics"
                element={
                  <ProtectedRoute roles={STAFF}>
                    <Analytics />
                  </ProtectedRoute>
                }
              />
              {PORTAL_PAGES.map(([path, Page]) => (
                <Route
                  key={path}
                  path={path}
                  element={
                    <ProtectedRoute roles={['patient']}>
                      <Page />
                    </ProtectedRoute>
                  }
                />
              ))}
              <Route path="*" element={<HomeRedirect />} />
            </Routes>
          </main>

          {/* Toast notifications */}
          <div className="toast-container-od" aria-live="polite" aria-atomic="true">
            {toasts.map((toast) => (
              <div key={toast.id} className="toast-item">
                <span style={{ fontSize: '16px' }}>
                  {toast.type === 'error' ? '⚠️' : toast.type === 'success' ? '✓' : 'ℹ️'}
                </span>
                <span>{toast.message}</span>
              </div>
            ))}
          </div>

          {/* Footer (omitted on login route) */}
          <AppFooter />
        </div>
      </BrowserRouter>
    </AppContext.Provider>
  );
}

function AppFooter() {
  const location = useLocation();
  if (location.pathname === '/login') return null;

  return (
    <footer className="app-footer">
      <div>
        OneDose is a prototype, not a medical device. All patient data is synthetic. The doctor always makes the final decision.
      </div>
    </footer>
  );
}
