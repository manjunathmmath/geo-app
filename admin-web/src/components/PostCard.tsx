import { useState } from 'react';
import type { Post } from '../api';

interface Props {
  post: Post;
  authorLabel: string;
  onApprove: () => Promise<void>;
  onReject: (reason: string) => Promise<void>;
}

function Media({ post }: { post: Post }) {
  const src = post.mediaUrl ?? undefined;
  if (post.type === 'TEXT') {
    return (
      <div className="media textpost">
        <p>{post.text}</p>
      </div>
    );
  }
  if (post.type === 'IMAGE') {
    return <img className="media" src={src} alt={post.caption ?? 'Post image'} loading="lazy" />;
  }
  if (post.type === 'VIDEO') {
    return <video className="media" src={src} controls preload="metadata" />;
  }
  return (
    <div className="media audio">
      <audio src={src} controls preload="metadata" />
    </div>
  );
}

export default function PostCard({ post, authorLabel, onApprove, onReject }: Props) {
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    try {
      await action();
    } finally {
      setBusy(false);
    }
  }

  const map = `https://www.openstreetmap.org/?mlat=${post.lat}&mlon=${post.lng}#map=19/${post.lat}/${post.lng}`;
  const canApprove = post.status !== 'APPROVED';
  const rejectLabel = post.status === 'APPROVED' ? 'Take down…' : 'Reject…';

  return (
    <article className="card post">
      <Media post={post} />
      <div className="post-body">
        <div className="row">
          <span className={`badge ${post.status.toLowerCase()}`}>{post.status}</span>
          <span className="badge type">{post.type}</span>
        </div>
        {post.type !== 'TEXT' && <h3>{post.caption ?? <span className="muted">(no caption)</span>}</h3>}
        <dl className="meta">
          <dt>By</dt>
          <dd>{authorLabel}</dd>
          <dt>Posted</dt>
          <dd>{new Date(post.createdAt).toLocaleString()}</dd>
          <dt>Location</dt>
          <dd>
            <a href={map} target="_blank" rel="noreferrer">
              {post.lat.toFixed(5)}, {post.lng.toFixed(5)}
            </a>
            {post.accuracyM != null && <span className="muted"> · GPS ±{Math.round(post.accuracyM)} m</span>}
          </dd>
        </dl>
        {post.rejectReason && <div className="alert">Reason: {post.rejectReason}</div>}

        {rejecting ? (
          <form
            className="row"
            onSubmit={(e) => {
              e.preventDefault();
              void run(() => onReject(reason.trim()));
            }}
          >
            <input
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Reason shown to the creator"
              maxLength={500}
              autoFocus
              required
            />
            <button className="btn danger" disabled={busy || !reason.trim()}>
              Confirm
            </button>
            <button type="button" className="btn" onClick={() => setRejecting(false)} disabled={busy}>
              Cancel
            </button>
          </form>
        ) : (
          <div className="row">
            {canApprove && (
              <button className="btn primary" disabled={busy} onClick={() => void run(onApprove)}>
                {post.status === 'REJECTED' ? 'Restore (approve)' : 'Approve'}
              </button>
            )}
            {post.status !== 'REJECTED' && (
              <button className="btn danger" disabled={busy} onClick={() => setRejecting(true)}>
                {rejectLabel}
              </button>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
