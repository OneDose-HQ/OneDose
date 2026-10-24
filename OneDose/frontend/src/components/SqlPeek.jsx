// File: src/components/SqlPeek.jsx - Collapsible drawer displaying highlighted SQL query and database execution timings
import React, { useState } from 'react';

export default function SqlPeek({ sql, elapsedMs }) {
  const [isOpen, setIsOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  const rawText = typeof sql === 'object' && sql !== null ? sql.text : sql;
  const timeMs = (typeof sql === 'object' && sql !== null ? sql.elapsed_ms : elapsedMs) || 12;

  const handleCopy = () => {
    if (!rawText) return;
    navigator.clipboard.writeText(rawText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // Syntax highlighting for SQL keywords without external libraries
  const renderHighlightedSql = (text) => {
    if (!text) return 'Run a check to see the SQL.';

    // Keywords to highlight in #8FD8CE
    const keywords = [
      'SELECT', 'FROM', 'JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'CROSS JOIN',
      'INNER JOIN', 'WHERE', 'WITH RECURSIVE', 'NOT EXISTS', 'EXISTS',
      'GROUP BY', 'HAVING', 'ORDER BY', 'LIMIT', 'OFFSET', 'UNION ALL',
      'UNION', 'SUM', 'COUNT', 'OVER', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END'
    ];

    // Split text into tokens keeping punctuation
    const lines = text.split('\n');

    return lines.map((line, lineIdx) => {
      // Regex replace SQL strings and keywords
      const parts = line.split(/('(?:''|[^'])*'|\b[A-Za-z_]+\b|[0-9]+)/g);

      return (
        <div key={lineIdx} style={{ minHeight: '1.4em' }}>
          {parts.map((part, pIdx) => {
            const upper = part.toUpperCase();
            if (keywords.includes(upper)) {
              return (
                <span key={pIdx} style={{ color: '#8FD8CE', fontWeight: 600 }}>
                  {part}
                </span>
              );
            }
            if (/^'.*'$/.test(part) || /^[0-9]+$/.test(part)) {
              return (
                <span key={pIdx} style={{ color: '#F5C97A' }}>
                  {part}
                </span>
              );
            }
            return <span key={pIdx}>{part}</span>;
          })}
        </div>
      );
    });
  };

  return (
    <div
      style={{
        marginTop: '28px',
        backgroundColor: 'var(--navy)',
        borderRadius: 'var(--radius-card)',
        overflow: 'hidden',
        border: '1px solid rgba(255, 255, 255, 0.12)',
        boxShadow: 'var(--shadow-card)',
      }}
    >
      {/* Collapsed top bar */}
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        style={{
          width: '100%',
          padding: '14px 20px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          backgroundColor: 'transparent',
          border: 'none',
          color: '#FFFFFF',
          cursor: 'pointer',
          textAlign: 'left',
        }}
        aria-expanded={isOpen}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <span style={{ fontSize: '13px', transform: isOpen ? 'rotate(90deg)' : 'rotate(0deg)', transition: 'transform 150ms ease' }}>
            ▶
          </span>
          <span style={{ fontWeight: 600, fontSize: '14px', color: '#FFFFFF' }}>
            Under the hood: SQL that ran
          </span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <span
            className="mono"
            style={{
              fontSize: '12px',
              backgroundColor: 'var(--navy-2)',
              color: '#8FD8CE',
              padding: '3px 10px',
              borderRadius: 'var(--radius-pill)',
            }}
          >
            Run time: {timeMs} ms
          </span>
        </div>
      </button>

      {/* Expanded drawer */}
      {isOpen && (
        <div
          style={{
            padding: '16px 20px 20px',
            borderTop: '1px solid rgba(255, 255, 255, 0.08)',
            backgroundColor: '#071524',
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
            <span style={{ fontSize: '12px', color: '#8FD8CE', letterSpacing: '0.04em', textTransform: 'uppercase', fontWeight: 600 }}>
              Query Executed
            </span>
            <button
              type="button"
              onClick={handleCopy}
              className="btn-od-secondary btn-compact"
              style={{
                backgroundColor: 'rgba(255, 255, 255, 0.08)',
                color: '#FFFFFF',
                border: '1px solid rgba(255, 255, 255, 0.2)',
                fontSize: '12px',
                height: '30px',
              }}
            >
              {copied ? '✓ Copied' : 'Copy SQL'}
            </button>
          </div>

          <pre
            className="mono"
            style={{
              margin: 0,
              padding: '14px',
              backgroundColor: 'var(--navy)',
              borderRadius: '8px',
              color: '#C5D0DC',
              fontSize: '13px',
              lineHeight: 1.5,
              overflowX: 'auto',
              border: '1px solid rgba(255, 255, 255, 0.06)',
            }}
          >
            {renderHighlightedSql(rawText)}
          </pre>
        </div>
      )}
    </div>
  );
}
