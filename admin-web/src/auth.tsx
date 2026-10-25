import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, loadTokens, saveTokens, type Me } from './api';

interface AuthContextValue {
  user: Me | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);

  const logout = useCallback(async () => {
    const tokens = loadTokens();
    saveTokens(null);
    setUser(null);
    if (tokens) {
      try {
        await api.logout(tokens.refreshToken);
      } catch {
        /* already invalid on the server: nothing more to do */
      }
    }
  }, []);

  // Restore the session on page load.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!loadTokens()) {
        setLoading(false);
        return;
      }
      try {
        const me = await api.me();
        if (cancelled) return;
        if (me.role === 'ADMIN') setUser(me);
        else await logout();
      } catch {
        saveTokens(null);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [logout]);

  const login = useCallback(async (email: string, password: string) => {
    const res = await api.login(email.trim(), password);
    if (res.user.role !== 'ADMIN') {
      // Valid account but not allowed here: do not keep its session.
      try {
        await api.logout(res.refreshToken);
      } catch {
        /* ignore */
      }
      throw new Error('This account is not an administrator.');
    }
    saveTokens({ accessToken: res.accessToken, refreshToken: res.refreshToken });
    setUser({ id: res.user.id, email: res.user.email ?? '', role: res.user.role });
  }, []);

  const value = useMemo(() => ({ user, loading, login, logout }), [user, loading, login, logout]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
