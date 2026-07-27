import { useEffect, useState } from 'react';

import { portalApi } from '../api/client';
import type { GetCreditBalanceResponse, GetUsageResponse, ListInvoicesResponse } from '../api/types';
import { useSession } from '../auth/session';
import { t } from '../i18n';

export function BillingPage() {
  const { workspaceId, hasPermission } = useSession();
  const [usage, setUsage] = useState<GetUsageResponse | null>(null);
  const [balance, setBalance] = useState<GetCreditBalanceResponse | null>(null);
  const [invoices, setInvoices] = useState<ListInvoicesResponse | null>(null);

  useEffect(() => {
    if (!workspaceId || !hasPermission('customer.billing:read')) {
      return;
    }
    void Promise.all([
      portalApi.usage(workspaceId).then(setUsage).catch(() => undefined),
      portalApi.balance(workspaceId).then(setBalance).catch(() => undefined),
      portalApi.invoices(workspaceId).then(setInvoices).catch(() => undefined),
    ]);
  }, [workspaceId, hasPermission]);

  return (
    <section className="panel">
      <h1>{t('nav.billing')}</h1>
      <div className="grid">
        <article>
          <h2>Usage</h2>
          <p>{usage?.status ?? 'loading'}</p>
        </article>
        <article>
          <h2>Balance</h2>
          <p>{balance?.status ?? 'loading'}</p>
        </article>
        <article>
          <h2>Invoices</h2>
          <ul>
            {(invoices?.items ?? []).map((invoice) => (
              <li key={invoice.id}>
                {invoice.id} · {invoice.status}
              </li>
            ))}
          </ul>
        </article>
      </div>
    </section>
  );
}
