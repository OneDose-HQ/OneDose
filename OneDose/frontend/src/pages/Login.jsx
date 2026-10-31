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
// SAFETY PIPELINE ANIMATION (left panel)
// A pill falls through five safety gates. The allergy gate turns amber and a
// shield stops it; a safer pill then passes every gate. Pure SVG + CSS (see
// the .od-* rules at the end of styles.css). No libraries, no text.
// ---------------------------------------------------------------------
function SafetyPipelineAnimation() {
  const gates = [
    { cy: 150, cls: 'od-g1' },
    { cy: 235, cls: 'od-g2' },
    { cy: 320, cls: 'od-g3' },
    { cy: 405, cls: 'od-g4' },
    { cy: 490, cls: 'od-g5' },
  ];
  return (
    <svg
      viewBox="0 0 400 640"
      role="img"
      aria-label="A medicine passes five safety checks; a conflict is caught and a safer medicine goes through"
      style={{ width: '100%', maxWidth: '440px', height: 'auto', maxHeight: '72vh' }}
    >
      {/* soft drifting dots */}
      <g>
        <circle className="od-dot" cx="50" cy="90" r="3" />
        <circle className="od-dot" cx="350" cy="70" r="4" />
        <circle className="od-dot" cx="70" cy="440" r="4" />
        <circle className="od-dot" cx="340" cy="560" r="3" />
        <circle className="od-dot" cx="120" cy="40" r="3" />
        <circle className="od-dot" cx="30" cy="300" r="3" />
        <circle className="od-dot" cx="372" cy="320" r="3" />
        <circle className="od-dot" cx="150" cy="610" r="4" />
        <circle className="od-dot" cx="300" cy="610" r="3" />
        <circle className="od-dot" cx="320" cy="190" r="3" />
        <circle className="od-dot" cx="90" cy="230" r="3" />
      </g>

      {/* guide line */}
      <line x1="200" y1="40" x2="200" y2="580" stroke="#2F7A68" strokeWidth="2" strokeDasharray="4 8" />

      {/* five gates */}
      {gates.map((g) => (
        <circle key={g.cls} className={`od-gate ${g.cls}`} cx="200" cy={g.cy} r="26" />
      ))}

      {/* gate icons: duplicate, interaction, allergy, condition, dose */}
      <circle className="od-ic" cx="192" cy="150" r="8" />
      <circle className="od-ic" cx="208" cy="150" r="8" />
      <path className="od-ic" d="M192 227 L208 243 M208 227 L192 243" />
      <path className="od-ic" d="M200 311 L210 328 H190 Z" />
      <path className="od-ic" d="M200 396 V414 M191 405 H209" />
      <path className="od-ic" d="M189 496 A11 11 0 0 1 211 496 M200 496 L206 485" />

      {/* shield that stops the first pill at the allergy gate */}
      <path
        className="od-shield"
        d="M200 276 L236 290 V322 C236 348 218 364 200 372 C182 364 164 348 164 322 V290 Z"
      />

      {/* first pill (stopped) */}
      <g className="od-p1">
        <g transform="translate(200 60)">
          <rect x="-13" y="-26" width="26" height="52" rx="13" fill="#5EEAD4" />
          <rect x="-13" y="0" width="26" height="26" rx="13" fill="#E8F5F1" />
          <rect x="-13" y="0" width="26" height="14" fill="#E8F5F1" />
          <rect x="-13" y="-14" width="26" height="14" fill="#5EEAD4" />
        </g>
      </g>

      {/* safer pill (passes every gate) */}
      <g className="od-p2">
        <g transform="translate(200 60)">
          <rect x="-13" y="-26" width="26" height="52" rx="13" fill="#86EFAC" />
          <rect x="-13" y="0" width="26" height="26" rx="13" fill="#FFFFFF" />
          <rect x="-13" y="0" width="26" height="14" fill="#FFFFFF" />
          <rect x="-13" y="-14" width="26" height="14" fill="#86EFAC" />
        </g>
      </g>

      {/* final check mark */}
      <g className="od-done">
        <circle cx="200" cy="590" r="24" fill="#14532D" stroke="#4ADE80" strokeWidth="3" />
        <path d="M189 590 L197 598 L212 582" fill="none" stroke="#4ADE80" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" />
      </g>
    </svg>
  );
}

// ---------------------------------------------------------------------
// LOGIN COMPONENT
// ---------------------------------------------------------------------
export default function Login() {
  const navigate = useNavigate();
  const { loginAuth, addToast } = useApp();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
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
      navigate(data.user.role === 'patient' ? '/portal' : '/prescribe');
    } catch (err) {
      setApiError(err.message || 'Invalid email or password');
    } finally {
      setLoading(false);
    }
  };

  const handleDemoPatient = async () => {
    setLoading(true);
    try {
      const data = await login('patient1@onedose.local', 'patient123');
      loginAuth(data);
      addToast('Signed in as a demo patient', 'success');
      navigate('/portal');
    } catch (err) {
      setApiError('Could not sign in with demo credentials');
    } finally {
      setLoading(false);
    }
  };

  const handleDemoClinician = async () => {
    setLoading(true);
    try {
      const data = await login('dr_demo@onedose.local', 'clinician123');
      loginAuth(data);
      addToast('Signed in as the demo clinician', 'success');
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
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: 0 }}>
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

        </div>

        {/* Safety pipeline animation (replaces the old illustration and text) */}
        <div style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <SafetyPipelineAnimation />
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
            Welcome back.
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
                Email
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  id="login-email"
                  type="email"
                  className={`form-control ${errors.email ? 'is-invalid' : ''}`}
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="name@example.com"
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
          <button
            type="button"
            className="btn-od-secondary"
            onClick={handleDemoPatient}
            disabled={loading}
            style={{ width: '100%', height: '44px', marginBottom: '20px' }}
          >
            Enter as demo patient
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
              For authorised users. Demo access uses synthetic records only; do not enter real patient information.
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
