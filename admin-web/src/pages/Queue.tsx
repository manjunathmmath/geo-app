import { useMemo, useState } from 'react';
import { api, type Post, type PostStatus } from '../api';
import PostCard from '../components/PostCard';
import { useLoad } from '../useLoad';

const LIMIT = 12;
const TABS: { status: PostStatus; label: string }[] = [
  { status: 'PENDING', label: 'Pending' },
  { status: 'APPROVED', label: 'Approved' },
  { status: 'REJECTED', label: 'Rejected' },
];

export default function Queue() {
  const [status, setStatus] = useState<PostStatus>('PENDING');
  const [offset, setOffset] = useState(0);
  const [notice, setNotice] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);

  const { data: posts, setData, error, loading, reload } = useLoad(
    () => api.listPosts(status, LIMIT, offset),
    [status, offset],
  );
  // The posts API returns author ids; one lookup of the first 100 users turns them into emails.
  const { data: users } = useLoad(() => api.listUsers(100, 0), []);
  const authors = useMemo(
    () => new Map((users ?? []).map((u) => [u.id, u.email ?? u.phone ?? u.id.slice(0, 8)])),
    [users],
  );

  function switchTab(next: PostStatus) {
    setStatus(next);
    setOffset(0);
    setNotice(null);
  }

  async function decide(post: Post, decision: 'APPROVE' | 'REJECT', reason?: string) {
    try {
      await api.review(post.id, decision, reason);
      const remaining = (posts ?? []).filter((p) => p.id !== post.id);
      setData(remaining);
      setNotice({
        kind: 'ok',
        text: `${decision === 'APPROVE' ? 'Approved' : 'Rejected'}: ${post.caption ?? post.text?.slice(0, 40) ?? post.id.slice(0, 8)}`,
      });
      if (remaining.length === 0) {
        if (offset > 0) setOffset(Math.max(0, offset - LIMIT));
        else reload();
      }
    } catch (e) {
      setNotice({ kind: 'error', text: e instanceof Error ? e.message : 'Action failed' });
    }
  }

  const list = posts ?? [];

  return (
    <>
      <div className="row between">
        <h2>Moderation</h2>
        <div className="tabs" role="tablist">
          {TABS.map((t) => (
            <button
              key={t.status}
              role="tab"
              aria-selected={status === t.status}
              className={status === t.status ? 'tab active' : 'tab'}
              onClick={() => switchTab(t.status)}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      {notice && (
        <div className={notice.kind === 'ok' ? 'alert ok' : 'alert'} role="status">
          {notice.text}
        </div>
      )}
      {error && <div className="alert">{error}</div>}
      {loading && !posts && <p className="muted">Loading…</p>}
      {!loading && !error && list.length === 0 && (
        <p className="muted empty">No {status.toLowerCase()} posts.</p>
      )}

      <div className="grid">
        {list.map((p) => (
          <PostCard
            key={p.id}
            post={p}
            authorLabel={authors.get(p.authorId) ?? p.authorId.slice(0, 8)}
            onApprove={() => decide(p, 'APPROVE')}
            onReject={(reason) => decide(p, 'REJECT', reason)}
          />
        ))}
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
