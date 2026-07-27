import { NavLink, Outlet } from 'react-router-dom';

import { useSession } from '../auth/session';

const NAV = [
  { to: '/', label: 'Overview', permission: 'operations.read' },
  { to: '/tasks', label: 'Tasks', permission: 'operations.read' },
  { to: '/workers', label: 'Workers', permission: 'operations.read' },
  { to: '/models', label: 'Models', permission: 'operations.read' },
  { to: '/fraud', label: 'Fraud', permission: 'operations.read' },
  { to: '/disputes', label: 'Disputes', permission: 'operations.read' },
  { to: '/reconciliation', label: 'Reconciliation', permission: 'operations.read' },
  { to: '/incidents', label: 'Incidents', permission: 'operations.read' },
  { to: '/approvals', label: 'Approvals', permission: 'operations.approve' },
  { to: '/emergency', label: 'Emergency', permission: 'operations.break_glass' },
];

export function AppShell() {
  const { authenticated, logout, hasPermission, mfaVerified } = useSession();
  if (!authenticated) return <Outlet />;

  return (
    <>
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>
      <header className="topbar">
        <strong>EdgeMint Operations</strong>
        <span className="badge">{mfaVerified ? 'MFA verified' : 'MFA required'}</span>
        <button type="button" onClick={logout}>
          Sign out
        </button>
      </header>
      <div className="layout">
        <nav aria-label="Operations">
          <ul>
            {NAV.filter((item) => hasPermission(item.permission)).map((item) => (
              <li key={item.to}>
                <NavLink to={item.to}>{item.label}</NavLink>
              </li>
            ))}
          </ul>
        </nav>
        <main id="main-content" tabIndex={-1}>
          <Outlet />
        </main>
      </div>
    </>
  );
}
