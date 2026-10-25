export type Role = 'CREATOR' | 'ADMIN';
export type UserStatus = 'ACTIVE' | 'BLOCKED';
export type PostStatus = 'PENDING' | 'APPROVED' | 'REJECTED';

export interface Post {
  id: string;
  authorId: string;
  type: 'IMAGE' | 'VIDEO' | 'AUDIO';
  mediaUrl: string;
  caption: string | null;
  lat: number;
  lng: number;
  accuracyM: number | null;
  status: PostStatus;
  createdAt: string;
  rejectReason: string | null;
  distanceM: number | null;
}

export interface User {
  id: string;
  email: string | null;
  phone: string | null;
  role: Role;
  status: UserStatus;
  createdAt: string;
}

export interface Me {
  id: string;
  email: string;
  role: Role;
}

interface Tokens {
  accessToken: string;
  refreshToken: string;
}

interface AuthResponse extends Tokens {
  user: User;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

// Tokens live in localStorage so a reload keeps you signed in. That is acceptable for an
// internal admin tool served from our own origin; revisit (httpOnly cookies) before wider use.
const TOKEN_KEY = 'geoapp.admin.tokens';

export function loadTokens(): Tokens | null {
  try {
    const raw = localStorage.getItem(TOKEN_KEY);
    return raw ? (JSON.parse(raw) as Tokens) : null;
  } catch {
    return null;
  }
}

export function saveTokens(tokens: Tokens | null): void {
  try {
    if (tokens) localStorage.setItem(TOKEN_KEY, JSON.stringify(tokens));
    else localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* storage unavailable: the session just won't survive a reload */
  }
}

let refreshing: Promise<boolean> | null = null;

/** One refresh at a time, even if several requests hit a 401 together. */
function refreshTokens(): Promise<boolean> {
  const current = loadTokens();
  if (!current) return Promise.resolve(false);
  if (!refreshing) {
    refreshing = (async () => {
      try {
        const res = await fetch('/api/auth/refresh', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken: current.refreshToken }),
        });
        if (!res.ok) {
          saveTokens(null);
          return false;
        }
        const data = (await res.json()) as AuthResponse;
        saveTokens({ accessToken: data.accessToken, refreshToken: data.refreshToken });
        return true;
      } catch {
        return false;
      } finally {
        refreshing = null;
      }
    })();
  }
  return refreshing;
}

async function request<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  const tokens = loadTokens();
  const headers = new Headers(init.headers);
  if (tokens) headers.set('Authorization', `Bearer ${tokens.accessToken}`);
  // FormData needs the browser to set its own multipart Content-Type (with the boundary).
  if (init.body && !(init.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  const res = await fetch(path, { ...init, headers });
  if (res.status === 401 && retry && tokens && (await refreshTokens())) {
    return request<T>(path, init, false);
  }
  if (!res.ok) {
    let message = res.statusText || `Request failed (${res.status})`;
    try {
      const body = (await res.json()) as { message?: string };
      if (body.message) message = body.message;
    } catch {
      /* not JSON */
    }
    throw new ApiError(res.status, message);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export const api = {
  login: (email: string, password: string) =>
    request<AuthResponse>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),
  logout: (refreshToken: string) =>
    request<void>('/api/auth/logout', { method: 'POST', body: JSON.stringify({ refreshToken }) }),
  me: () => request<Me>('/api/auth/me'),

  listPosts: (status: PostStatus, limit: number, offset: number) =>
    request<Post[]>(`/api/admin/posts?status=${status}&limit=${limit}&offset=${offset}`),
  review: (id: string, decision: 'APPROVE' | 'REJECT', reason?: string) =>
    request<Post>(`/api/admin/posts/${id}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision, reason }),
    }),

  /** Admin posts are published immediately; the server decides that from the role. */
  createPost: (p: {
    file: File;
    lat: number;
    lng: number;
    accuracy?: number | null;
    caption?: string;
    authorId?: string;
  }) => {
    const body = new FormData();
    if (p.authorId) body.append('authorId', p.authorId);
    body.append('file', p.file);
    body.append('lat', String(p.lat));
    body.append('lng', String(p.lng));
    if (p.accuracy != null) body.append('accuracy', String(p.accuracy));
    if (p.caption?.trim()) body.append('caption', p.caption.trim());
    return request<Post>('/api/posts', { method: 'POST', body });
  },

  listUsers: (limit: number, offset: number) =>
    request<User[]>(`/api/admin/users?limit=${limit}&offset=${offset}`),
  updateUser: (id: string, patch: { status?: UserStatus; role?: Role }) =>
    request<User>(`/api/admin/users/${id}`, { method: 'PATCH', body: JSON.stringify(patch) }),
};
