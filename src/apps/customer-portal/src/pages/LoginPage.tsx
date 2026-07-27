import { Navigate } from 'react-router-dom';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

export function LoginPage() {
  const { authenticated, loginWithOidc, loginDev } = useSession();

  if (authenticated) {
    return <Navigate to="/" replace />;
  }

  return (
    <section className="panel login-panel">
      <h1>{t('login.title')}</h1>
      <p>OIDC Authorization Code with PKCE completes on the server. Only the opaque BFF cookie is stored in the browser.</p>
      <div className="login-actions">
        <button
          type="button"
          className="primary-button"
          onClick={() => {
            trackEvent('portal.login.oidc');
            loginWithOidc();
          }}
        >
          {t('login.oidc')}
        </button>
        <button
          type="button"
          className="secondary-button"
          onClick={() => {
            trackEvent('portal.login.dev');
            void loginDev('00000000-0000-0000-0000-00000000000b');
          }}
        >
          {t('login.dev')}
        </button>
      </div>
    </section>
  );
}
