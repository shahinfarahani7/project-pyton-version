import { useEffect, useState } from 'react';

import { portalApi } from '../api/client';
import type { ListDisputesResponse } from '../api/types';
import { useSession } from '../auth/session';
import { t } from '../i18n';

export function DisputesPage() {
  const { workspaceId, hasPermission } = useSession();
  const [items, setItems] = useState<ListDisputesResponse | null>(null);

  useEffect(() => {
    if (!workspaceId || !hasPermission('customer.billing:read')) {
      return;
    }
    portalApi
      .disputes(workspaceId)
      .then(setItems)
      .catch(() => setItems({ items: [], page: { limit: 25, hasMore: false } }));
  }, [workspaceId, hasPermission]);

  return (
    <section className="panel">
      <h1>{t('nav.disputes')}</h1>
      <table>
        <thead>
          <tr>
            <th scope="col">Dispute</th>
            <th scope="col">Status</th>
          </tr>
        </thead>
        <tbody>
          {(items?.items ?? []).map((item) => (
            <tr key={item.id}>
              <td>{item.id}</td>
              <td>{item.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
