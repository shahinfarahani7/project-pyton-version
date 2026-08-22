<script setup>
import { computed } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
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

const usedMicro = computed(() => usage.value?.computeMicroEur ?? 0);
const limitMicro = computed(() => {
  const available = balance.value?.availableMicroEur ?? 0;
  const reserved = balance.value?.reservedMicroEur ?? 0;
  return Math.max(usedMicro.value + available + reserved, 1);
});
const usagePct = computed(() => Math.min(100, Math.round((usedMicro.value / limitMicro.value) * 100)));
</script>

<template>
  <section class="em-page em-page--billing">
    <div class="em-layout-billing-top">
      <article class="md-card em-plan-card">
        <p class="em-plan-card__label">{{ t('billing.currentPlan') }}</p>
        <h2 class="em-plan-card__title">{{ t('billing.enterprisePlan') }}</h2>
        <p class="em-plan-card__price">{{ t('billing.planPrice') }}</p>
        <p class="md-hint">{{ usage?.period ?? '—' }}</p>
      </article>

      <article class="md-card">
      <div class="em-usage-gauge__header">
        <span>{{ t('billing.usageSummary') }}</span>
        <strong>{{ formatMicroEur(usedMicro) }} / {{ formatMicroEur(limitMicro) }}</strong>
      </div>
      <div class="em-usage-gauge__track">
        <div class="em-usage-gauge__fill" :style="{ width: `${usagePct}%` }" />
      </div>
      <p class="md-hint">{{ usagePct }}% · {{ formatNumber(usage?.taskCount) }} {{ t('dashboard.taskRuns') }}</p>
      </article>
    </div>

    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 6rem" /></div>

    <article v-else class="md-card">
      <h2 class="em-section-title">{{ t('billing.invoicesTitle') }}</h2>
      <EmptyState
        v-if="!(invoices?.items?.length)"
        :title="t('billing.invoicesEmpty')"
        icon="receipt_long"
      />
      <ul v-else class="em-invoice-list">
        <li v-for="invoice in invoices.items" :key="invoice.id">
          <div>
            <strong>{{ invoice.id }}</strong>
            <p class="md-hint">{{ formatMicroEur(invoice.amountDueMicroEur) }}</p>
          </div>
          <StatusChip :status="invoice.status" />
        </li>
      </ul>
      <button type="button" class="md-btn md-btn-filled md-btn-block" disabled>
        {{ t('billing.viewInvoices') }}
      </button>
    </article>
  </section>
</template>
