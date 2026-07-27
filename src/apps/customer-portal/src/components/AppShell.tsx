import { NavLink, Outlet } from 'react-router-dom';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import { SkipToContent } from './SkipToContent';
import { WorkspaceSwitcher } from './WorkspaceSwitcher';

const navItems = [
  { to: '/', labelKey: 'nav.dashboard', permission: null },
  { to: '/tasks', labelKey: 'nav.tasks', permission: 'customer.tasks:read' },
  { to: '/files', labelKey: 'nav.files', permission: 'customer.tasks:read' },
  { to: '/webhooks', labelKey: 'nav.webhooks', permission: 'customer.webhooks:read' },
  { to: '/api-keys', labelKey: 'nav.apiKeys', permission: 'customer.apikeys:read' },
  { to: '/billing', labelKey: 'nav.billing', permission: 'customer.billing:read' },
  { to: '/disputes', labelKey: 'nav.disputes', permission: 'customer.billing:read' },
  { to: '/team', labelKey: 'nav.team', permission: 'customer.team:read' },
  { to: '/settings', labelKey: 'nav.settings', permission: null },
] as const;

export function AppShell() {
  const { authenticated, logout, hasPermission } = useSession();

  if (!authenticated) {
    return <Outlet />;
  }

  return (
    <>
      <SkipToContent />
      <header className="topbar">
        <div className="brand">
          <strong>EdgeMint</strong>
          <span className="badge">{t('app.title')}</span>
        </div>
        <WorkspaceSwitcher />
        <button type="button" className="secondary-button" onClick={() => void logout()}>
          Sign out
        </button>
      </header>
      <div className="layout">
        <nav aria-label="Primary">
          <ul className="nav-list">
            {navItems
              .filter((item) => item.permission === null || hasPermission(item.permission))
              .map((item) => (
                <li key={item.to}>
                  <NavLink end={item.to === '/'} to={item.to}>
                    {t(item.labelKey)}
                  </NavLink>
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
