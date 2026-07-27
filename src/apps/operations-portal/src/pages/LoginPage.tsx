import { Navigate } from 'react-router-dom';

import { useSession } from '../auth/session';

export function LoginPage() {
  const { authenticated, loginSso, loginDev } = useSession();
  if (authenticated) return <Navigate to="/" replace />;

  return (
    <section className="panel login-panel">
      <h1>Operator sign-in</h1>
      <p>SSO with MFA completes on the server. Provider tokens never reach browser JavaScript.</p>
      <div className="actions">
        <button type="button" className="primary" onClick={loginSso}>
          Continue with SSO + MFA
        </button>
        <button type="button" onClick={loginDev}>
          Development sign-in
        </button>
      </div>
    </section>
  );
}
