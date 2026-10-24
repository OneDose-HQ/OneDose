// File: src/components/BrandSearch.jsx - Debounced brand search input with highlighted keyboard dropdown
import React, { useState, useEffect, useRef } from 'react';
import { searchBrands } from '../api.js';

export default function BrandSearch({ onSelect, disabled = false }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [isOpen, setIsOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState(0);

  const requestCounter = useRef(0);
  const dropdownRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < 2) {
      setResults([]);
      setIsOpen(false);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    const currentReq = ++requestCounter.current;

    const timer = setTimeout(async () => {
      try {
        const data = await searchBrands(trimmed);
        if (currentReq === requestCounter.current) {
          setResults(data);
          setIsOpen(true);
          setSelectedIndex(0);
        }
      } catch (err) {
        if (currentReq === requestCounter.current) {
          setResults([]);
        }
      } finally {
        if (currentReq === requestCounter.current) {
          setIsLoading(false);
        }
      }
    }, 250);

    return () => clearTimeout(timer);
  }, [query]);

  // Handle outside click to close dropdown
  useEffect(() => {
    function handleClickOutside(e) {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(e.target) &&
        !inputRef.current.contains(e.target)
      ) {
        setIsOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleKeyDown = (e) => {
    if (!isOpen || results.length === 0) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setSelectedIndex((prev) => (prev + 1) % results.length);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setSelectedIndex((prev) => (prev - 1 + results.length) % results.length);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (results[selectedIndex]) {
        handleSelectBrand(results[selectedIndex]);
      }
    } else if (e.key === 'Escape') {
      setIsOpen(false);
    }
  };

  const handleSelectBrand = (brand) => {
    setQuery(brand.brand_name);
    setIsOpen(false);
    if (onSelect) {
      onSelect(brand);
    }
  };

  // Helper to highlight matching substrings
  const highlightMatch = (text, matchStr) => {
    if (!matchStr.trim()) return text;
    const parts = text.split(new RegExp(`(${matchStr})`, 'gi'));
    return parts.map((part, i) =>
      part.toLowerCase() === matchStr.toLowerCase() ? (
        <span key={i} style={{ color: 'var(--brand-dark)', fontWeight: 700, textDecoration: 'underline' }}>
          {part}
        </span>
      ) : (
        part
      )
    );
  };

  return (
    <div style={{ position: 'relative', width: '100%' }}>
      <label htmlFor="brand-search-input" className="form-label">
        Brand name
      </label>
      <div style={{ position: 'relative' }}>
        <input
          id="brand-search-input"
          ref={inputRef}
          type="text"
          className="form-control"
          placeholder="e.g. Combiflam, Dolo 650..."
          value={query}
          disabled={disabled}
          onChange={(e) => setQuery(e.target.value)}
          onFocus={() => {
            if (results.length > 0) setIsOpen(true);
          }}
          onKeyDown={handleKeyDown}
          autoComplete="off"
          aria-autocomplete="list"
          aria-expanded={isOpen}
          aria-haspopup="listbox"
        />

        {isLoading && (
          <span
            style={{
              position: 'absolute',
              right: '12px',
              top: '12px',
              fontSize: '12px',
              color: 'var(--muted)',
            }}
          >
            Searching...
          </span>
        )}
      </div>

      {/* Dropdown list matching Image 3 */}
      {isOpen && (
        <div
          ref={dropdownRef}
          style={{
            position: 'absolute',
            top: 'calc(100% + 4px)',
            left: 0,
            right: 0,
            backgroundColor: '#FFFFFF',
            border: '1px solid var(--border-strong)',
            borderRadius: 'var(--radius-control)',
            boxShadow: 'var(--shadow-dropdown)',
            maxHeight: '280px',
            overflowY: 'auto',
            zIndex: 1050,
          }}
          role="listbox"
        >
          {results.length > 0 ? (
            results.map((brand, idx) => {
              const isSelected = idx === selectedIndex;
              return (
                <div
                  key={brand.brand_id || idx}
                  onClick={() => handleSelectBrand(brand)}
                  onMouseEnter={() => setSelectedIndex(idx)}
                  style={{
                    padding: '10px 14px',
                    cursor: 'pointer',
                    backgroundColor: isSelected ? 'var(--brand-tint)' : '#FFFFFF',
                    borderBottom: idx < results.length - 1 ? '1px solid var(--border)' : 'none',
                    transition: 'background-color 100ms ease',
                  }}
                  role="option"
                  aria-selected={isSelected}
                >
                  <div style={{ fontWeight: 700, fontSize: '14px', color: 'var(--ink)' }}>
                    {highlightMatch(brand.brand_name, query)}
                  </div>
                  <div className="mono" style={{ fontSize: '12px', color: 'var(--muted)', marginTop: '2px' }}>
                    {brand.ingredients
                      ? brand.ingredients.map((i) => `${i.name} ${i.strength_mg} mg`).join(' + ')
                      : brand.strength}
                  </div>
                </div>
              );
            })
          ) : (
            <div style={{ padding: '12px 14px', fontSize: '13px', color: 'var(--muted)' }}>
              No brands found matching "{query}"
            </div>
          )}
        </div>
      )}
    </div>
  );
}
