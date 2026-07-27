import { useEffect, useState } from 'react';

import { portalApi } from '../api/client';
import type { ListTasksResponse } from '../api/types';
import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

export function TasksPage() {
  const { workspaceId, hasPermission } = useSession();
  const [tasks, setTasks] = useState<ListTasksResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!workspaceId || !hasPermission('customer.tasks:read')) {
      return;
    }
    trackEvent('portal.page.tasks');
    portalApi
      .tasks(workspaceId)
      .then(setTasks)
      .catch((err: Error) => setError(err.message));
  }, [workspaceId, hasPermission]);

  return (
    <section className="panel">
      <h1>{t('nav.tasks')}</h1>
      {error ? <p role="alert">{error}</p> : null}
      <table>
        <caption className="visually-hidden">Task list</caption>
        <thead>
          <tr>
            <th scope="col">Task ID</th>
            <th scope="col">Type</th>
            <th scope="col">Lifecycle</th>
            <th scope="col">Execution</th>
          </tr>
        </thead>
        <tbody>
          {(tasks?.items ?? []).map((task) => (
            <tr key={task.id}>
              <td>{task.id}</td>
              <td>{task.taskType}</td>
              <td>{task.lifecycleStatus}</td>
              <td>{task.executionStatus}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
