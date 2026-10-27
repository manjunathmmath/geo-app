import { useEffect, useState, type ChangeEvent, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { api, ApiError, type Post } from '../api';
import { useAuth } from '../auth';
import { useLoad } from '../useLoad';

const MAX_BYTES = 50 * 1024 * 1024;
const ACCEPT = 'image/jpeg,image/png,image/webp,video/mp4,audio/mp4,audio/mpeg,audio/aac,audio/wav,audio/ogg,.m4a';

function geoErrorMessage(err: GeolocationPositionError): string {
  switch (err.code) {
    case err.PERMISSION_DENIED:
      return 'Location permission was denied. Allow it in the browser, or type the coordinates.';
    case err.POSITION_UNAVAILABLE:
      return 'Your position is not available right now. Type the coordinates instead.';
    default:
      return 'Finding your position took too long. Try again or type the coordinates.';
  }
}

function Preview({ file, url }: { file: File; url: string }) {
  if (file.type.startsWith('image/')) return <img className="media" src={url} alt="Selected file preview" />;
  if (file.type.startsWith('video/')) return <video className="media" src={url} controls preload="metadata" />;
  return (
    <div className="media audio">
      <audio src={url} controls preload="metadata" />
    </div>
  );
}

export default function NewPost() {
  const { user: me, logout } = useAuth();
  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [caption, setCaption] = useState('');
  const [lat, setLat] = useState('');
  const [lng, setLng] = useState('');
  const [accuracy, setAccuracy] = useState<number | null>(null);
  const [locating, setLocating] = useState(false);
  const [locError, setLocError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<Post | null>(null);
  const [authorId, setAuthorId] = useState(''); // '' = post as myself
  const [mode, setMode] = useState<'media' | 'text'>('media');
  const [text, setText] = useState('');

  // Active users the admin can post as (the first 100; enough for now).
  const { data: users } = useLoad(() => api.listUsers(100, 0), []);
  const authors = (users ?? []).filter((u) => u.status === 'ACTIVE' && u.id !== me?.id);
  const authorLabel = (id: string) => {
    const u = (users ?? []).find((x) => x.id === id);
    return u ? (u.email ?? u.phone ?? id.slice(0, 8)) : 'another user';
  };

  // Revoke the temporary preview URL when the file changes or the page closes.
  useEffect(() => {
    if (!file) {
      setPreviewUrl(null);
      return;
    }
    const url = URL.createObjectURL(file);
    setPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  function pickFile(e: ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0] ?? null;
    setError(null);
    if (f && f.size > MAX_BYTES) {
      setFile(null);
      setError('That file is larger than 50 MB.');
      return;
    }
    setFile(f);
  }

  function useMyLocation() {
    if (!navigator.geolocation) {
      setLocError('This browser cannot provide a location. Type the coordinates instead.');
      return;
    }
    setLocating(true);
    setLocError(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLat(pos.coords.latitude.toFixed(6));
        setLng(pos.coords.longitude.toFixed(6));
        setAccuracy(pos.coords.accuracy);
        setLocating(false);
      },
      (err) => {
        setLocError(geoErrorMessage(err));
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  }

  // Hand-typed coordinates have no measured accuracy.
  function editCoordinate(setter: (v: string) => void, value: string) {
    setter(value);
    setAccuracy(null);
  }

  const latNum = Number(lat);
  const lngNum = Number(lng);
  const coordsValid =
    lat.trim() !== '' && lng.trim() !== '' && Number.isFinite(latNum) && Number.isFinite(lngNum) &&
    Math.abs(latNum) <= 90 && Math.abs(lngNum) <= 180;

  const hasContent = mode === 'media' ? file !== null : text.trim().length > 0;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!coordsValid || !hasContent) return;
    setBusy(true);
    setError(null);
    try {
      setCreated(
        await api.createPost({
          file: mode === 'media' ? (file ?? undefined) : undefined,
          text: mode === 'text' ? text : undefined,
          lat: latNum,
          lng: lngNum,
          accuracy,
          caption: mode === 'media' ? caption : undefined,
          authorId: authorId || undefined,
        }),
      );
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) void logout();
      else setError(err instanceof Error ? err.message : 'Could not create the post');
    } finally {
      setBusy(false);
    }
  }

  function reset() {
    setFile(null);
    setCaption('');
    setText('');
    setCreated(null);
    setError(null);
  }

  if (created) {
    const map = `https://www.openstreetmap.org/?mlat=${created.lat}&mlon=${created.lng}#map=19/${created.lat}/${created.lng}`;
    return (
      <>
        <h2>New post</h2>
        <div className="alert ok" role="status">
          Posted{authorId ? ` as ${authorLabel(authorId)}` : ''} and published ({created.status}). Visitors within
          20 m of{' '}
          <a href={map} target="_blank" rel="noreferrer">
            {created.lat.toFixed(5)}, {created.lng.toFixed(5)}
          </a>{' '}
          can see it now.
        </div>
        <div className="row">
          <button className="btn primary" onClick={reset}>
            Post another
          </button>
          <Link className="btn" to="/moderation">
            Back to moderation
          </Link>
        </div>
      </>
    );
  }

  return (
    <>
      <h2>New post</h2>
      <p className="muted">
        Admin posts are published immediately. Visitors see the post when they are within 20 m of the location below.
      </p>
      <form className="card newpost" onSubmit={submit}>
        <div className="tabs" role="tablist" aria-label="Kind of post">
          <button
            type="button"
            role="tab"
            aria-selected={mode === 'media'}
            className={mode === 'media' ? 'tab active' : 'tab'}
            onClick={() => setMode('media')}
          >
            Photo, audio or video
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === 'text'}
            className={mode === 'text' ? 'tab active' : 'tab'}
            onClick={() => setMode('text')}
          >
            Text only
          </button>
        </div>

        {mode === 'media' ? (
          <>
            <label>
              File
              <input type="file" accept={ACCEPT} onChange={pickFile} />
            </label>
            {file && previewUrl && <Preview file={file} url={previewUrl} />}
          </>
        ) : (
          <label>
            Text
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              maxLength={1000}
              rows={5}
              placeholder="Write what you want people at this spot to read"
            />
            <span className="small muted">{text.length} / 1000</span>
          </label>
        )}

        <label>
          Post as
          <select value={authorId} onChange={(e) => setAuthorId(e.target.value)}>
            <option value="">Myself ({me?.email})</option>
            {authors.map((u) => (
              <option key={u.id} value={u.id}>
                {u.email ?? u.phone ?? u.id.slice(0, 8)}
              </option>
            ))}
          </select>
        </label>

        {mode === 'media' && (
          <label>
            Caption (optional)
            <textarea value={caption} onChange={(e) => setCaption(e.target.value)} maxLength={500} rows={2} />
          </label>
        )}

        <fieldset>
          <legend>Location</legend>
          <div className="row">
            <button type="button" className="btn" onClick={useMyLocation} disabled={locating}>
              {locating ? 'Finding position…' : 'Use my current location'}
            </button>
            {accuracy != null && <span className="muted small">GPS accuracy ±{Math.round(accuracy)} m</span>}
          </div>
          {locError && <div className="alert">{locError}</div>}
          <div className="two">
            <label>
              Latitude
              <input
                inputMode="decimal"
                value={lat}
                onChange={(e) => editCoordinate(setLat, e.target.value)}
                placeholder="12.971600"
                required
              />
            </label>
            <label>
              Longitude
              <input
                inputMode="decimal"
                value={lng}
                onChange={(e) => editCoordinate(setLng, e.target.value)}
                placeholder="77.594600"
                required
              />
            </label>
          </div>
          {(lat !== '' || lng !== '') && !coordsValid && (
            <div className="alert">Latitude must be between -90 and 90, longitude between -180 and 180.</div>
          )}
        </fieldset>

        {error && (
          <div className="alert" role="alert">
            {error}
          </div>
        )}
        <div className="row">
          <button className="btn primary" disabled={busy || !hasContent || !coordsValid}>
            {busy ? 'Posting…' : 'Publish post'}
          </button>
        </div>
      </form>
    </>
  );
}
