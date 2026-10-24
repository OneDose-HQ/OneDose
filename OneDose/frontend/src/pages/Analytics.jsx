// File: src/pages/Analytics.jsx - Clinical safety analytics with Chart.js override rates, severity breakdown, and audit log
import React, { useState, useEffect, useRef } from 'react';
import Chart from 'chart.js/auto';
import { useApp } from '../App.jsx';
import { getOverrideStats, getAuditLog } from '../api.js';

export default function Analytics() {
  const { auth, addToast } = useApp();
  const isAdmin = auth?.user?.role === 'admin';

  const [stats, setStats] = useState(null);
  const [auditLogs, setAuditLogs] = useState([]);
  const [auditFilter, setAuditFilter] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  const barChartRef = useRef(null);
  const doughnutChartRef = useRef(null);
  const barInstance = useRef(null);
  const doughnutInstance = useRef(null);

  useEffect(() => {
    async function loadData() {
      setIsLoading(true);
      try {
        const statsData = await getOverrideStats();
        setStats(statsData);

        if (isAdmin) {
          const logsData = await getAuditLog();
          setAuditLogs(logsData);
        }
      } catch (err) {
        addToast(err.message, 'error');
      } finally {
        setIsLoading(false);
      }
    }
    loadData();
  }, [isAdmin]);

  // Initialize and update Chart.js instances
  useEffect(() => {
    if (!stats) return;

    // Destroy existing instances
    if (barInstance.current) {
      barInstance.current.destroy();
      barInstance.current = null;
    }
    if (doughnutInstance.current) {
      doughnutInstance.current.destroy();
      doughnutInstance.current = null;
    }

    // Chart 1: Horizontal Bar - Override rate per check type
    if (barChartRef.current) {
      const labels = stats.per_check.map((c) => c.label);
      const data = stats.per_check.map((c) => c.override_rate);

      barInstance.current = new Chart(barChartRef.current, {
        type: 'bar',
        data: {
          labels,
          datasets: [
            {
              label: 'Override Rate (%)',
              data,
              backgroundColor: [
                '#0E9F8E',
                '#14B8A6',
                '#2DD4BF',
                '#5EEAD4',
                '#99F6E4',
              ],
              borderRadius: 6,
            },
          ],
        },
        options: {
          indexAxis: 'y',
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                label: (ctx) => ` ${ctx.raw}% override rate`,
              },
            },
          },
          scales: {
            x: {
              grid: { color: '#E3E9F0' },
              ticks: { callback: (val) => `${val}%` },
              max: 40,
            },
            y: {
              grid: { display: false },
              ticks: { font: { weight: '600' } },
            },
          },
        },
      });
    }

    // Chart 2: Doughnut - Alerts by severity
    if (doughnutChartRef.current) {
      const labels = stats.by_severity.map((s) => s.label);
      const data = stats.by_severity.map((s) => s.count);

      doughnutInstance.current = new Chart(doughnutChartRef.current, {
        type: 'doughnut',
        data: {
          labels,
          datasets: [
            {
              data,
              backgroundColor: [
                '#B91C1C', // Critical
                '#B8420C', // Major
                '#8A5A00', // Moderate
                '#1D4ED8', // Minor
              ],
              borderWidth: 2,
              borderColor: '#FFFFFF',
            },
          ],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: 'right',
              labels: {
                boxWidth: 14,
                font: { size: 12, family: 'Inter' },
              },
            },
            tooltip: {
              callbacks: {
                label: (ctx) => ` ${ctx.label}: ${ctx.raw} alerts`,
              },
            },
          },
          cutout: '68%',
        },
      });
    }

    return () => {
      if (barInstance.current) barInstance.current.destroy();
      if (doughnutInstance.current) doughnutInstance.current.destroy();
    };
  }, [stats]);

  const filteredLogs = auditLogs.filter(
    (log) =>
      log.actor.toLowerCase().includes(auditFilter.toLowerCase()) ||
      log.action.toLowerCase().includes(auditFilter.toLowerCase()) ||
      log.entity.toLowerCase().includes(auditFilter.toLowerCase()) ||
      log.hash.toLowerCase().includes(auditFilter.toLowerCase())
  );

  return (
    <div className="app-container">
      {/* Title & Insight banner */}
      <h1 className="page-title">Prescription Safety Analytics</h1>
      <p className="page-subtitle" style={{ marginBottom: '14px' }}>
        System-wide alert triggers, override frequencies, and rule efficacy monitoring.
      </p>

      <div
        style={{
          backgroundColor: '#E6F6F4',
          border: '1px solid #99F6E4',
          borderRadius: 'var(--radius-control)',
          padding: '12px 18px',
          fontSize: '13px',
          color: 'var(--brand-dark)',
          fontWeight: 500,
          marginBottom: '24px',
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
        }}
      >
        <span>💡</span>
        <span>
          <strong>Insight:</strong> High override rates signal alert fatigue; review these rules first.
        </span>
      </div>

      {isLoading ? (
        <div className="od-card" style={{ padding: '48px', textAlign: 'center', color: 'var(--muted)' }}>
          Loading safety telemetry and rule statistics...
        </div>
      ) : (
        <>
          {/* KPI Cards Row */}
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
              gap: '18px',
              marginBottom: '24px',
            }}
          >
            <div className="od-card" style={{ margin: 0 }}>
              <span className="section-label">TOTAL ALERTS</span>
              <div style={{ fontSize: '32px', fontWeight: 700, color: 'var(--ink)' }}>
                {stats?.totals.alerts.toLocaleString()}
              </div>
              <div style={{ fontSize: '12px', color: 'var(--muted)', marginTop: '4px' }}>
                All rules evaluated across prescriptions
              </div>
            </div>

            <div className="od-card" style={{ margin: 0 }}>
              <span className="section-label">TOTAL OVERRIDES</span>
              <div style={{ fontSize: '32px', fontWeight: 700, color: 'var(--major)' }}>
                {stats?.totals.overrides.toLocaleString()}
              </div>
              <div style={{ fontSize: '12px', color: 'var(--muted)', marginTop: '4px' }}>
                Clinically acknowledged with written reasons
              </div>
            </div>

            <div className="od-card" style={{ margin: 0 }}>
              <span className="section-label">OVERALL OVERRIDE RATE</span>
              <div style={{ fontSize: '32px', fontWeight: 700, color: 'var(--brand)' }}>
                {stats?.totals.override_rate}%
              </div>
              <div style={{ fontSize: '12px', color: 'var(--muted)', marginTop: '4px' }}>
                Hospital benchmark threshold: &lt;20%
              </div>
            </div>

            <div className="od-card" style={{ margin: 0 }}>
              <span className="section-label">HIGHEST-OVERRIDE CHECK</span>
              <div style={{ fontSize: '24px', fontWeight: 700, color: 'var(--ink)' }}>
                {stats?.totals.highest_override_check}
              </div>
              <div style={{ fontSize: '12px', color: 'var(--muted)', marginTop: '4px' }}>
                30.9% override on elderly age bands
              </div>
            </div>
          </div>

          {/* Charts Row */}
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(380px, 1fr))',
              gap: '24px',
              marginBottom: '24px',
            }}
          >
            {/* Chart 1 */}
            <div className="od-card" style={{ margin: 0 }}>
              <h3 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '6px' }}>
                Override rate per check type
              </h3>
              <p style={{ fontSize: '12px', color: 'var(--muted)', marginBottom: '16px' }}>
                Percentage of alerts overridden by clinicians for each safety engine category.
              </p>
              <div style={{ position: 'relative', height: '240px' }}>
                <canvas ref={barChartRef} />
              </div>
            </div>

            {/* Chart 2 */}
            <div className="od-card" style={{ margin: 0 }}>
              <h3 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '6px' }}>
                Alerts by severity
              </h3>
              <p style={{ fontSize: '12px', color: 'var(--muted)', marginBottom: '16px' }}>
                Distribution across critical, major, moderate, and minor tiers.
              </p>
              <div style={{ position: 'relative', height: '240px' }}>
                <canvas ref={doughnutChartRef} />
              </div>
            </div>
          </div>

          {/* Most Overridden Alerts Table */}
          <div className="od-card" style={{ marginBottom: '24px' }}>
            <h3 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '4px' }}>
              Most overridden alerts
            </h3>
            <p style={{ fontSize: '12px', color: 'var(--muted)', marginBottom: '16px' }}>
              High-frequency overrides candidate for clinical guideline tuning.
            </p>

            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border)' }}>
                    <th style={{ textAlign: 'left', padding: '10px 8px', color: 'var(--muted)' }}>
                      Ingredient Pair / Rule
                    </th>
                    <th style={{ textAlign: 'left', padding: '10px 8px', color: 'var(--muted)' }}>
                      Check Type
                    </th>
                    <th style={{ textAlign: 'right', padding: '10px 8px', color: 'var(--muted)' }}>
                      Count
                    </th>
                    <th style={{ textAlign: 'left', padding: '10px 16px', color: 'var(--muted)', width: '220px' }}>
                      Relative Volume
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {stats?.top_overridden.map((item, idx) => {
                    const maxVal = stats.top_overridden[0]?.count || 100;
                    const pct = (item.count / maxVal) * 100;
                    return (
                      <tr key={idx} style={{ borderBottom: '1px solid var(--border)' }}>
                        <td style={{ padding: '12px 8px', fontWeight: 600, color: 'var(--ink)' }}>
                          {item.ingredient_pair}
                        </td>
                        <td style={{ padding: '12px 8px', color: 'var(--ink-soft)' }}>
                          <span className="badge bg-light text-dark border">
                            {item.check_type}
                          </span>
                        </td>
                        <td className="mono" style={{ textAlign: 'right', padding: '12px 8px', fontWeight: 700 }}>
                          {item.count}
                        </td>
                        <td style={{ padding: '12px 16px' }}>
                          <div style={{ width: '100%', height: '8px', backgroundColor: '#E2E8F0', borderRadius: '4px', overflow: 'hidden' }}>
                            <div style={{ width: `${pct}%`, height: '100%', backgroundColor: 'var(--brand)', borderRadius: '4px' }} />
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>

          {/* Admin Only Audit Log Table */}
          {isAdmin && (
            <div className="od-card">
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px', flexWrap: 'wrap', gap: '10px' }}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <h3 style={{ fontSize: '16px', fontWeight: 700, margin: 0 }}>
                      Tamper-Evident Audit Log
                    </h3>
                    <span className="badge bg-dark text-white rounded-pill" style={{ fontSize: '10px', fontWeight: 600 }}>
                      hash-chained
                    </span>
                  </div>
                  <p style={{ fontSize: '12px', color: 'var(--muted)', margin: '4px 0 0 0' }}>
                    Read-only cryptographically linked audit trail verified against SHA-256 signatures.
                  </p>
                </div>

                <input
                  type="text"
                  className="form-control"
                  style={{ width: '240px', height: '36px', fontSize: '13px' }}
                  placeholder="Filter actor, action, hash..."
                  value={auditFilter}
                  onChange={(e) => setAuditFilter(e.target.value)}
                />
              </div>

              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--border)' }}>
                      <th style={{ textAlign: 'left', padding: '8px', color: 'var(--muted)' }}>Time</th>
                      <th style={{ textAlign: 'left', padding: '8px', color: 'var(--muted)' }}>Actor</th>
                      <th style={{ textAlign: 'left', padding: '8px', color: 'var(--muted)' }}>Action</th>
                      <th style={{ textAlign: 'left', padding: '8px', color: 'var(--muted)' }}>Entity</th>
                      <th style={{ textAlign: 'right', padding: '8px', color: 'var(--muted)' }}>Hash Prefix</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredLogs.map((log) => (
                      <tr key={log.id} style={{ borderBottom: '1px solid var(--border)' }}>
                        <td className="mono" style={{ padding: '10px 8px', color: 'var(--muted)', fontSize: '12px' }}>
                          {new Date(log.at).toLocaleTimeString('en-GB')}
                        </td>
                        <td style={{ padding: '10px 8px', fontWeight: 600, color: 'var(--ink)' }}>
                          {log.actor}
                        </td>
                        <td style={{ padding: '10px 8px' }}>
                          <span
                            className="badge"
                            style={{
                              backgroundColor: log.action === 'OVERRIDE' ? 'var(--major-tint)' : log.action === 'INSERT' ? 'var(--ok-tint)' : '#EEF2F6',
                              color: log.action === 'OVERRIDE' ? 'var(--major)' : log.action === 'INSERT' ? 'var(--ok)' : 'var(--ink)',
                              border: '1px solid var(--border)',
                              fontSize: '11px',
                            }}
                          >
                            {log.action}
                          </span>
                        </td>
                        <td className="mono" style={{ padding: '10px 8px', color: 'var(--ink-soft)' }}>
                          {log.entity}
                        </td>
                        <td className="mono" style={{ textAlign: 'right', padding: '10px 8px', color: 'var(--brand-dark)', fontWeight: 600 }}>
                          #{log.hash}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
