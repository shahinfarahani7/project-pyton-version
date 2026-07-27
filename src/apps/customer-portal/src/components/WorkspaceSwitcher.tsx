import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

export function WorkspaceSwitcher() {
  const { workspaces, workspaceId, switchWorkspace } = useSession();
  if (workspaces.length === 0) {
    return null;
  }

  return (
    <label className="workspace-switcher">
      <span className="visually-hidden">{t('workspace.switch')}</span>
      <select
        aria-label={t('workspace.switch')}
        value={workspaceId ?? ''}
        onChange={(event) => {
          const next = event.target.value;
          trackEvent('portal.workspace.switch', { workspaceId: next });
          void switchWorkspace(next);
        }}
      >
        {workspaces.map((workspace) => (
          <option key={workspace.id} value={workspace.id}>
            {workspace.name}
          </option>
        ))}
      </select>
    </label>
  );
}
