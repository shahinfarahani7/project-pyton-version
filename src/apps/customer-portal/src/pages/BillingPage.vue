<script setup>
import { computed } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
import PageHeader from '../components/ui/PageHeader.vue';
import StatCard from '../components/ui/StatCard.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';
import { formatMicroEur, formatNumber } from '../utils/format';

const session = useSession();

const { data: usage, loading: usageLoading } = useAsyncResource(
  () => portalApi.usage(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.billing:read')) },
);

const { data: balance, loading: balanceLoading } = useAsyncResource(
  () => portalApi.balance(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.billing:read')) },
);

const { data: invoices, loading: invoicesLoading } = useAsyncResource(
  () => portalApi.invoices(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.billing:read')) },
);

const loading = computed(
  () => usageLoading.value || balanceLoading.value || invoicesLoading.value,
);
</script>

<template>
  <section>
    <PageHeader :title="t('nav.billing')" :subtitle="t('billing.subtitle')" />
    <div v-if="loading" class="stat-grid">
      <div v-for="n in 3" :key="n" class="md-skeleton" />
    </div>
    <div v-else class="stat-grid">
      <StatCard
        :label="t('billing.usage')"
        :value="usage?.period ?? '—'"
        :hint="`${formatNumber(usage?.taskCount)} ${t('dashboard.taskRuns')}`"
        icon="monitoring"
      />
      <StatCard
        :label="t('billing.available')"
        :value="formatMicroEur(balance?.availableMicroEur)"
        icon="account_balance_wallet"
      />
      <StatCard
        :label="t('billing.compute')"
        :value="formatMicroEur(usage?.computeMicroEur)"
        icon="memory"
      />
    </div>

    <article class="md-card">
      <PageHeader :title="t('billing.invoicesTitle')" />
      <EmptyState
        v-if="!(invoices?.items?.length)"
        :title="t('billing.invoicesEmpty')"
        icon="receipt_long"
      />
      <div v-else class="md-table-wrap">
        <table class="md-table">
          <thead>
            <tr>
              <th scope="col">{{ t('billing.invoiceId') }}</th>
              <th scope="col">{{ t('billing.status') }}</th>
              <th scope="col">{{ t('billing.amount') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="invoice in invoices.items" :key="invoice.id">
              <td>{{ invoice.id }}</td>
              <td><StatusChip :status="invoice.status" /></td>
              <td>{{ formatMicroEur(invoice.amountDueMicroEur) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </section>
</template>
