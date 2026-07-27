import { useSession } from '../auth/session';
import { t } from '../i18n';

export function DashboardPage() {
  const { workspaceId, sessionPublicId, authorizationGeneration } = useSession();

  return (
    <section className="panel">
      <h1>{t('nav.dashboard')}</h1>
      <p>Authenticated BFF session with opaque cookie. Provider tokens never reach browser JavaScript.</p>
      <dl className="meta-grid">
        <div>
          <dt>Session</dt>
          <dd>{sessionPublicId}</dd>
        </div>
        <div>
          <dt>Workspace</dt>
          <dd>{workspaceId}</dd>
        </div>
        <div>
          <dt>Authorization generation</dt>
          <dd>{authorizationGeneration}</dd>
        </div>
      </dl>
    </section>
  );
}
