import { Navigate, Outlet } from 'react-router-dom';

import { useSession } from '../auth/session';

export function ProtectedRoute() {
  const { authenticated, mfaVerified } = useSession();
  if (!authenticated) return <Navigate to="/login" replace />;
  if (!mfaVerified) return <Navigate to="/login" replace />;
  return <Outlet />;
}
