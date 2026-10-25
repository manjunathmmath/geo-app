import { useState } from 'react';
import { api, type Role, type User, type UserStatus } from '../api';
import { useAuth } from '../auth';
import { useLoad } from '../useLoad';

const LIMIT = 25;

export default function Users() {
  const { user: me } = useAuth();
  const [offset, setOffset] = useState(0);
  const [notice, setNotice] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const { data: users, setData, error, loading } = useLoad(() => api.listUsers(LIMIT, offset), [offset]);
  const list = users ?? [];

  async function change(user: User, patch: { status?: UserStatus; role?: Role }, confirmText: string) {
    if (!window.confirm(confirmText)) return;
    try {
      const updated = await api.updateUser(user.id, patch);
      setData(list.map((u) => (u.id === updated.id ? updated : u)));
      setNotice({ kind: 'ok', text: `Updated ${updated.email ?? updated.id.slice(0, 8)}` });
    } catch (e) {
      setNotice({ kind: 'error', text: e instanceof Error ? e.message : 'Update failed' });
    }
  }

  return (
    <>
      <h2>Users</h2>
      {notice && (
        <div className={notice.kind === 'ok' ? 'alert ok' : 'alert'} role="status">
          {notice.text}
        </div>
      )}
      {error && <div className="alert">{error}</div>}
      {loading && !users && <p className="muted">Loading…</p>}

      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>Email</th>
              <th>Role</th>
              <th>Status</th>
              <th>Joined</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {list.map((u) => {
              const isMe = u.id === me?.id;
              const name = u.email ?? u.phone ?? u.id.slice(0, 8);
              return (
                <tr key={u.id}>
                  <td>
                    {name}
                    {isMe && <span className="muted"> (you)</span>}
                  </td>
                  <td>
                    <span className={`badge ${u.role === 'ADMIN' ? 'approved' : 'type'}`}>{u.role}</span>
                  </td>
                  <td>
                    <span className={`badge ${u.status === 'ACTIVE' ? 'approved' : 'rejected'}`}>{u.status}</span>
                  </td>
                  <td className="small">{new Date(u.createdAt).toLocaleDateString()}</td>
                  <td className="actions">
                    {u.status === 'ACTIVE' ? (
                      <button
                        className="btn danger small"
                        disabled={isMe}
                        title={isMe ? 'You cannot block yourself' : undefined}
                        onClick={() =>
                          void change(u, { status: 'BLOCKED' }, `Block ${name}? They lose access immediately.`)
                        }
                      >
                        Block
                      </button>
                    ) : (
                      <button
                        className="btn small"
                        onClick={() => void change(u, { status: 'ACTIVE' }, `Unblock ${name}?`)}
                      >
                        Unblock
                      </button>
                    )}
                    {u.role === 'CREATOR' ? (
                      <button
                        className="btn small"
                        onClick={() =>
                          void change(u, { role: 'ADMIN' }, `Make ${name} an administrator? They can moderate and manage users.`)
                        }
                      >
                        Make admin
                      </button>
                    ) : (
                      <button
                        className="btn small"
                        disabled={isMe}
                        title={isMe ? 'You cannot demote yourself' : undefined}
                        onClick={() => void change(u, { role: 'CREATOR' }, `Remove administrator rights from ${name}?`)}
                      >
                        Make creator
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="row pager">
        <button className="btn" disabled={offset === 0 || loading} onClick={() => setOffset(Math.max(0, offset - LIMIT))}>
          ← Previous
        </button>
        <span className="muted small">
          Showing {list.length === 0 ? 0 : offset + 1}–{offset + list.length}
        </span>
        <button className="btn" disabled={list.length < LIMIT || loading} onClick={() => setOffset(offset + LIMIT)}>
          Next →
        </button>
      </div>
    </>
  );
}
