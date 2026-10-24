// File: src/pages/Login.jsx - Authentication page matching Image 1 two-panel clinician portal
import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useApp } from '../App.jsx';
import { login } from '../api.js';
import { validateLogin } from '../validators.js';

// ---------------------------------------------------------------------
// INLINE SVGS FOR LOGIN SCREEN
// ---------------------------------------------------------------------
function CapsuleIconWhite({ size = 20 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7Z" />
      <path d="m8.5 8.5 7 7" />
    </svg>
  );
}

function StethoscopeIcon({ size = 22, color = 'var(--login-brand)' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4.5 3v5a3.5 3.5 0 0 0 7 0V3" />
      <path d="M8 11.5v3a4.5 4.5 0 0 0 9 0v-1.5" />
      <circle cx="17" cy="10" r="2" />
    </svg>
  );
}

function MailIcon({ size = 18, color = 'var(--muted)' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect width="20" height="16" x="2" y="4" rx="2" />
      <path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7" />
    </svg>
  );
}

function EyeIcon({ size = 18, color = 'var(--muted)' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

function EyeOffIcon({ size = 18, color = 'var(--muted)' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9.88 9.88a3 3 0 1 0 4.24 4.24" />
      <path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68" />
      <path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61" />
      <line x1="2" x2="22" y1="2" y2="22" />
    </svg>
  );
}

function LockIcon({ size = 16, color = 'var(--login-brand)' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
  );
}

// ---------------------------------------------------------------------
// LOGIN COMPONENT
// ---------------------------------------------------------------------
export default function Login() {
  const navigate = useNavigate();
  const { loginAuth, addToast } = useApp();

  const [email, setEmail] = useState('shruti.kapoor@cedar.example');
  const [password, setPassword] = useState('password123');
  const [showPassword, setShowPassword] = useState(false);
  const [keepSignedIn, setKeepSignedIn] = useState(true);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState({});
  const [apiError, setApiError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setApiError('');

    const validation = validateLogin({ email, password });
    if (!validation.valid) {
      setErrors(validation.errors);
      return;
    }
    setErrors({});
    setLoading(true);

    try {
      const data = await login(email, password);
      loginAuth(data);
      addToast(`Welcome back, ${data.user.name}`, 'success');
      navigate('/prescribe');
    } catch (err) {
      setApiError(err.message || 'Invalid email or password');
    } finally {
      setLoading(false);
    }
  };

  const handleDemoClinician = async () => {
    setLoading(true);
    try {
      const data = await login('dr.rao@onedose.local', 'clinician123');
      loginAuth(data);
      addToast('Signed in as Dr. Rao (Demo Clinician)', 'success');
      navigate('/prescribe');
    } catch (err) {
      setApiError('Could not sign in with demo credentials');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ minHeight: '100vh', display: 'flex', width: '100%' }}>
      {/* ----------------------------------------------------------------- */}
      {/* LEFT PANEL (Dark Forest Green - Image 1)                         */}
      {/* ----------------------------------------------------------------- */}
      <div
        className="d-none d-lg-flex"
        style={{
          width: '50%',
          backgroundColor: 'var(--forest)',
          color: '#FFFFFF',
          padding: '48px 64px',
          flexDirection: 'column',
          justifyContent: 'space-between',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        {/* Top brand header */}
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '48px' }}>
            <div
              style={{
                width: '36px',
                height: '36px',
                borderRadius: '8px',
                backgroundColor: 'var(--forest-2)',
                border: '1px solid var(--forest-line)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <CapsuleIconWhite size={20} />
            </div>
            <span style={{ fontSize: '22px', fontWeight: 700, letterSpacing: '-0.02em', color: '#FFFFFF' }}>
              OneDose
            </span>
          </div>

          <div
            style={{
              fontSize: '11px',
              fontWeight: 700,
              letterSpacing: '0.12em',
              textTransform: 'uppercase',
              color: '#86B5A9',
              marginBottom: '16px',
            }}
          >
            A CLEARER CLINICAL PICTURE
          </div>

          <h1
            style={{
              fontSize: '46px',
              fontWeight: 300,
              lineHeight: 1.15,
              letterSpacing: '-0.03em',
              color: '#FFFFFF',
              margin: '0 0 20px 0',
            }}
          >
            One patient.<br />
            Every ingredient.<br />
            An informed decision.
          </h1>

          <p
            style={{
              fontSize: '15px',
              lineHeight: 1.6,
              color: 'rgba(255, 255, 255, 0.7)',
              maxWidth: '430px',
              margin: 0,
            }}
          >
            Bring medicines, patient context and transparent safety checks into one considered view.
          </p>
        </div>

        {/* Central Illustration: Concentric rings with 4 node tiles */}
        <div style={{ position: 'relative', height: '320px', margin: '20px auto', width: '100%', maxWidth: '420px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {/* Concentric rings */}
          <div
            style={{
              position: 'absolute',
              width: '320px',
              height: '320px',
              borderRadius: '50%',
              border: '1px solid var(--forest-line)',
              pointerEvents: 'none',
            }}
          />
          <div
            style={{
              position: 'absolute',
              width: '240px',
              height: '240px',
              borderRadius: '50%',
              border: '1px solid var(--forest-line)',
              pointerEvents: 'none',
            }}
          />

          {/* Radiating spoke lines */}
          <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none' }}>
            <line x1="210" y1="160" x2="210" y2="40" stroke="rgba(255,255,255,0.18)" strokeWidth="1" />
            <line x1="210" y1="160" x2="210" y2="280" stroke="rgba(255,255,255,0.18)" strokeWidth="1" />
            <line x1="210" y1="160" x2="60" y2="160" stroke="rgba(255,255,255,0.18)" strokeWidth="1" />
            <line x1="210" y1="160" x2="360" y2="160" stroke="rgba(255,255,255,0.18)" strokeWidth="1" />
          </svg>

          {/* Top Node: Database */}
          <div
            style={{
              position: 'absolute',
              top: '20px',
              left: '50%',
              transform: 'translateX(-50%)',
              width: '40px',
              height: '40px',
              borderRadius: '10px',
              backgroundColor: 'var(--forest-2)',
              border: '1px solid var(--forest-line)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth="2">
              <ellipse cx="12" cy="5" rx="9" ry="3" />
              <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5" />
              <path d="M3 12c0 1.66 4 3 9 3s9-1.34 9-3" />
            </svg>
          </div>

          {/* Left Node: Capsule */}
          <div
            style={{
              position: 'absolute',
              left: '40px',
              top: '50%',
              transform: 'translateY(-50%)',
              width: '40px',
              height: '40px',
              borderRadius: '10px',
              backgroundColor: 'var(--forest-2)',
              border: '1px solid var(--forest-line)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <CapsuleIconWhite size={18} />
          </div>

          {/* Right Node: Shield with check */}
          <div
            style={{
              position: 'absolute',
              right: '40px',
              top: '50%',
              transform: 'translateY(-50%)',
              width: '40px',
              height: '40px',
              borderRadius: '10px',
              backgroundColor: 'var(--forest-2)',
              border: '1px solid var(--forest-line)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth="2">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              <path d="m9 12 2 2 4-4" />
            </svg>
          </div>

          {/* Bottom Node: Heart with pulse */}
          <div
            style={{
              position: 'absolute',
              bottom: '20px',
              left: '50%',
              transform: 'translateX(-50%)',
              width: '40px',
              height: '40px',
              borderRadius: '10px',
              backgroundColor: 'var(--forest-2)',
              border: '1px solid var(--forest-line)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth="2">
              <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
              <path d="M3.22 12H9.5l1.5-3 2 6.5 1.5-3.5h6.28" />
            </svg>
          </div>

          {/* Center Card: "A complete patient view" */}
          <div
            style={{
              width: '230px',
              height: '92px',
              backgroundColor: '#FFFFFF',
              borderRadius: '12px',
              boxShadow: '0 12px 28px rgba(0,0,0,0.22)',
              padding: '12px 14px',
              zIndex: 2,
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'space-between',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <div
                style={{
                  width: '32px',
                  height: '32px',
                  borderRadius: '8px',
                  backgroundColor: '#E6F6F4',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--brand)" strokeWidth="2">
                  <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
                  <circle cx="12" cy="7" r="4" />
                </svg>
              </div>
              <div>
                <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--ink)', lineHeight: 1.2 }}>
                  A complete patient view
                </div>
                <div style={{ fontSize: '11px', color: 'var(--muted)', marginTop: '2px' }}>
                  Context before a decision
                </div>
              </div>
            </div>

            {/* Skeleton lines */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
              <div style={{ width: '85%', height: '5px', backgroundColor: '#E2E8F0', borderRadius: '3px' }} />
              <div style={{ width: '55%', height: '5px', backgroundColor: '#EDF2F7', borderRadius: '3px' }} />
            </div>
          </div>
        </div>

        {/* Bottom panel footer note */}
        <div style={{ borderTop: '1px solid var(--forest-line)', paddingTop: '20px' }}>
          <div style={{ fontSize: '13px', fontWeight: 600, color: '#FFFFFF', marginBottom: '4px' }}>
            Database-led. Clinician-decided.
          </div>
          <div style={{ fontSize: '12px', color: 'rgba(255, 255, 255, 0.65)', lineHeight: 1.5 }}>
            SQL evaluates the rules. AI only phrases existing alert explanations. You retain the final decision.
          </div>
        </div>
      </div>

      {/* ----------------------------------------------------------------- */}
      {/* RIGHT PANEL (Light Form - Image 1)                                */}
      {/* ----------------------------------------------------------------- */}
      <div
        style={{
          flex: 1,
          backgroundColor: 'var(--login-bg)',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          padding: '32px 48px',
        }}
      >
        {/* Top bar */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span
            style={{
              fontSize: '11px',
              fontWeight: 700,
              letterSpacing: '0.08em',
              padding: '4px 10px',
              borderRadius: 'var(--radius-pill)',
              backgroundColor: 'var(--login-brand-tint)',
              color: 'var(--login-brand)',
            }}
          >
            DEMO WORKSPACE
          </span>
          <a
            href="#help"
            onClick={(e) => e.preventDefault()}
            style={{ fontSize: '13px', color: 'var(--muted)', textDecoration: 'none' }}
          >
            Need help? ↗
          </a>
        </div>

        {/* Center Login Form */}
        <div style={{ width: '100%', maxWidth: '420px', margin: '40px auto' }}>
          {/* Stethoscope tile */}
          <div
            style={{
              width: '42px',
              height: '42px',
              borderRadius: '10px',
              backgroundColor: 'var(--login-brand-tint)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: '20px',
            }}
          >
            <StethoscopeIcon size={24} color="var(--login-brand)" />
          </div>

          <h2
            style={{
              fontSize: '28px',
              fontWeight: 500,
              color: 'var(--forest)',
              lineHeight: 1.2,
              marginBottom: '6px',
            }}
          >
            Welcome back, clinician.
          </h2>
          <p style={{ fontSize: '14px', color: 'var(--muted)', marginBottom: '28px' }}>
            Sign in to your OneDose workspace.
          </p>

          {apiError && (
            <div
              className="alert alert-danger py-2 px-3 mb-3"
              style={{ fontSize: '13px', borderRadius: 'var(--radius-control)' }}
              role="alert"
            >
              {apiError}
            </div>
          )}

          <form onSubmit={handleSubmit} noValidate>
            {/* Work email field */}
            <div style={{ marginBottom: '18px' }}>
              <label htmlFor="login-email" className="form-label">
                Work email
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  id="login-email"
                  type="email"
                  className={`form-control ${errors.email ? 'is-invalid' : ''}`}
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="name@hospital.example"
                  style={{ paddingRight: '38px' }}
                  aria-describedby={errors.email ? 'email-error' : undefined}
                />
                <span style={{ position: 'absolute', right: '12px', top: '13px', pointerEvents: 'none' }}>
                  <MailIcon />
                </span>
              </div>
              {errors.email && (
                <div id="email-error" className="invalid-feedback">
                  {errors.email}
                </div>
              )}
            </div>

            {/* Password field */}
            <div style={{ marginBottom: '10px' }}>
              <label htmlFor="login-password" className="form-label">
                Password
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  id="login-password"
                  type={showPassword ? 'text' : 'password'}
                  className={`form-control ${errors.password ? 'is-invalid' : ''}`}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••••••"
                  style={{ paddingRight: '40px' }}
                  aria-describedby={errors.password ? 'password-error' : undefined}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  style={{
                    position: 'absolute',
                    right: '10px',
                    top: '10px',
                    background: 'none',
                    border: 'none',
                    cursor: 'pointer',
                    padding: '4px',
                  }}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                </button>
              </div>
              {errors.password && (
                <div id="password-error" className="invalid-feedback">
                  {errors.password}
                </div>
              )}
            </div>

            {/* Forgot password */}
            <div style={{ textAlign: 'left', marginBottom: '16px' }}>
              <a
                href="#forgot"
                onClick={(e) => e.preventDefault()}
                style={{ fontSize: '13px', color: 'var(--login-brand)', fontWeight: 500 }}
              >
                Forgot password?
              </a>
            </div>

            {/* Keep signed in */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '22px' }}>
              <input
                id="keep-signed-in"
                type="checkbox"
                checked={keepSignedIn}
                onChange={(e) => setKeepSignedIn(e.target.checked)}
                style={{ width: '16px', height: '16px', accentColor: 'var(--login-brand)', cursor: 'pointer' }}
              />
              <label htmlFor="keep-signed-in" style={{ fontSize: '13px', color: 'var(--ink-soft)', cursor: 'pointer', margin: 0 }}>
                Keep me signed in on this device
              </label>
            </div>

            {/* Submit button */}
            <button
              type="submit"
              disabled={loading}
              style={{
                width: '100%',
                height: '44px',
                backgroundColor: 'var(--login-brand)',
                color: '#FFFFFF',
                border: 'none',
                borderRadius: 'var(--radius-control)',
                fontSize: '14px',
                fontWeight: 600,
                cursor: loading ? 'not-allowed' : 'pointer',
                transition: 'background-color 150ms ease',
              }}
            >
              {loading ? 'Signing in...' : 'Sign in to OneDose →'}
            </button>
          </form>

          {/* Divider */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              margin: '22px 0',
              color: 'var(--muted)',
              fontSize: '12px',
            }}
          >
            <div style={{ flex: 1, height: '1px', backgroundColor: 'var(--border)' }} />
            <span style={{ padding: '0 12px' }}>or explore the prototype</span>
            <div style={{ flex: 1, height: '1px', backgroundColor: 'var(--border)' }} />
          </div>

          {/* Demo clinician button */}
          <button
            type="button"
            onClick={handleDemoClinician}
            disabled={loading}
            style={{
              width: '100%',
              height: '44px',
              backgroundColor: '#FFFFFF',
              color: 'var(--ink)',
              border: '1px solid var(--border-strong)',
              borderRadius: 'var(--radius-control)',
              fontSize: '14px',
              fontWeight: 500,
              cursor: loading ? 'not-allowed' : 'pointer',
              marginBottom: '20px',
              transition: 'background-color 150ms ease',
            }}
          >
            Enter as demo clinician
          </button>

          {/* Authorised notice box */}
          <div
            style={{
              backgroundColor: 'var(--login-brand-tint)',
              borderRadius: 'var(--radius-control)',
              padding: '12px 14px',
              display: 'flex',
              alignItems: 'flex-start',
              gap: '10px',
            }}
          >
            <div style={{ marginTop: '2px' }}>
              <LockIcon size={16} color="var(--login-brand)" />
            </div>
            <div style={{ fontSize: '12px', color: 'var(--login-brand)', lineHeight: 1.45 }}>
              For authorised clinicians. Demo access uses synthetic records only; do not enter real patient information.
            </div>
          </div>
        </div>

        {/* Bottom copyright footer */}
        <div style={{ textAlign: 'center', fontSize: '11px', color: 'var(--muted)', lineHeight: 1.6 }}>
          <div>Privacy · Terms · OneDose © 2026</div>
          <div>Demo prototype, not a medical device. No validated clinical recommendations.</div>
        </div>
      </div>
    </div>
  );
}
