import { useSession } from '../auth/session';

export function DashboardPage() {
  const { operatorId, role } = useSession();
  return (
    <section className="panel">
      <h1>Operations overview</h1>
      <p>Least-privilege operator session with SSO/MFA and audited administrative actions.</p>
      <dl>
        <dt>Operator</dt>
        <dd>{operatorId}</dd>
        <dt>Role</dt>
        <dd>{role}</dd>
      </dl>
    </section>
  );
}
