import { Navigate, NavLink, Outlet, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth';
import Login from './pages/Login';
import NewPost from './pages/NewPost';
import Queue from './pages/Queue';
import Users from './pages/Users';

function RequireAuth() {
  const { user, loading } = useAuth();
  if (loading) return <div className="center muted">Loading…</div>;
  if (!user) return <Navigate to="/login" replace />;
  return <Outlet />;
}

function Layout() {
  const { user, logout } = useAuth();
  return (
    <>
      <header className="topbar">
        <strong className="brand">GeoApp Admin</strong>
        <nav>
          <NavLink to="/moderation">Moderation</NavLink>
          <NavLink to="/new">New post</NavLink>
          <NavLink to="/users">Users</NavLink>
        </nav>
        <span className="spacer" />
        <span className="muted small">{user?.email}</span>
        <button className="btn" onClick={() => void logout()}>
          Sign out
        </button>
      </header>
      <main className="content">
        <Outlet />
      </main>
    </>
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<RequireAuth />}>
        <Route element={<Layout />}>
          <Route index element={<Navigate to="/moderation" replace />} />
          <Route path="/moderation" element={<Queue />} />
          <Route path="/new" element={<NewPost />} />
          <Route path="/users" element={<Users />} />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
