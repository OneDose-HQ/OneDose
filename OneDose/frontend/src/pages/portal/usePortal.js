// File: src/pages/portal/usePortal.js - Small data-loading hook shared by the patient portal pages
// Inputs: a function that returns a promise (an api.js call) and a list of values that should trigger a reload.
// Outputs: { data, error, loading, reload }
import { useCallback, useEffect, useState } from 'react';

export default function usePortal(loader, deps = []) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError('');
    loader()
      .then((d) => { if (alive) setData(d); })
      .catch((e) => { if (alive) setError(e.message || 'Something went wrong'); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);

  const reload = useCallback(() => setTick((n) => n + 1), []);
  return { data, error, loading, reload };
}
