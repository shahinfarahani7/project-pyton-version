import { useEffect, useState } from 'react';

import { portalApi } from '../api/client';
import type { ListWebhookEndpointsResponse } from '../api/types';
import { useSession } from '../auth/session';
import { t } from '../i18n';

export function WebhooksPage() {
  const { hasPermission } = useSession();
  const [items, setItems] = useState<ListWebhookEndpointsResponse | null>(null);

  useEffect(() => {
    if (!hasPermission('customer.webhooks:read')) {
      return;
    }
    portalApi.webhooks().then(setItems).catch(() => setItems({ items: [], page: { limit: 25, hasMore: false } }));
  }, [hasPermission]);

  return (
    <section className="panel">
      <h1>{t('nav.webhooks')}</h1>
      <table>
        <thead>
          <tr>
            <th scope="col">Endpoint</th>
            <th scope="col">Status</th>
            <th scope="col">Version</th>
          </tr>
        </thead>
        <tbody>
          {(items?.items ?? []).map((item) => (
            <tr key={item.id}>
              <td>{item.id}</td>
              <td>{item.status}</td>
              <td>{item.version}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
