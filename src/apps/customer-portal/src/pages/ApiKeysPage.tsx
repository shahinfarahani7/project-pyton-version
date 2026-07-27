import { useEffect, useState } from 'react';

import { portalApi } from '../api/client';
import type { ListApiKeysResponse } from '../api/types';
import { useSession } from '../auth/session';
import { t } from '../i18n';

export function ApiKeysPage() {
  const { hasPermission } = useSession();
  const [items, setItems] = useState<ListApiKeysResponse | null>(null);

  useEffect(() => {
    if (!hasPermission('customer.apikeys:read')) {
      return;
    }
    portalApi.apiKeys().then(setItems).catch(() => setItems({ items: [], page: { limit: 25, hasMore: false } }));
  }, [hasPermission]);

  return (
    <section className="panel">
      <h1>{t('nav.apiKeys')}</h1>
      <p>API key secrets are shown once at creation and never stored in browser storage.</p>
      <table>
        <thead>
          <tr>
            <th scope="col">Key</th>
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
