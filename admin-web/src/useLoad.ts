import { useEffect, useState } from 'react';
import { ApiError } from './api';
import { useAuth } from './auth';

/** Loads data when `deps` change. A 401 that survives the token refresh signs the admin out. */
export function useLoad<T>(fn: () => Promise<T>, deps: unknown[]) {
  const { logout } = useAuth();
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fn()
      .then((d) => {
        if (!cancelled) setData(d);
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        if (e instanceof ApiError && e.status === 401) void logout();
        else setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);

  return { data, setData, error, loading, reload: () => setTick((t) => t + 1) };
}
