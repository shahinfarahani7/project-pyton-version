<script setup>
import { computed } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
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
const invoiceItems = computed(() => invoices.value?.items ?? []);
const openInvoices = computed(() =>
  invoiceItems.value.filter((invoice) => String(invoice.status || '').toLowerCase() === 'open'),
);
const amountDueMicro = computed(() =>
  openInvoices.value.reduce((sum, invoice) => {
    const amount = invoice.amountDueMicroEur;
    return Number.isInteger(amount) ? sum + amount : sum;
  }, 0),
);

function invoiceStatus(status) {
  const value = String(status || '').toLowerCase();
  if (value === 'paid') return { label: t('billing.statusPaid'), tone: '' };
  if (value === 'open') return { label: t('billing.statusOpen'), tone: 'warn' };
  if (value === 'draft') return { label: t('billing.statusDraft'), tone: 'neutral' };
  if (value === 'void' || value === 'failed') return { label: String(status), tone: 'bad' };
  return { label: status ? String(status) : '—', tone: 'neutral' };
}

function invoicePeriod(invoice) {
  return invoice.period || invoice.billingPeriod || '—';
}

function invoiceDue(invoice) {
  return invoice.dueDate || invoice.dueAt || '—';
}
</script>

<template>
  <section class="em-page em-page--billing">
    <div class="fn-billing-grid">
      <article class="md-card fn-balance-card">
        <div class="fn-card-head">
          <h2 class="em-section-title">{{ t('billing.available') }}</h2>
        </div>
        <p class="fn-money">{{ formatMicroEur(balance?.availableMicroEur) }}</p>
        <p class="fn-card-note">{{ t('billing.availableHint') }}</p>
        <dl class="fn-kv">
          <div>
            <dt>{{ t('dashboard.reserved') }}</dt>
            <dd>{{ formatMicroEur(balance?.reservedMicroEur) }}</dd>
          </div>
          <div>
            <dt>{{ t('billing.computePeriod') }}</dt>
            <dd>{{ formatMicroEur(usedMicro) }}</dd>
          </div>
        </dl>
      </article>

      <article class="md-card">
        <div class="fn-card-head">
          <h2 class="em-section-title">{{ t('billing.creditAtWork') }}</h2>
        </div>
        <p class="fn-card-sub">{{ t('billing.creditAtWorkBody') }}</p>
        <dl class="fn-kv">
          <div>
            <dt>{{ t('billing.currency') }}</dt>
            <dd>EUR</dd>
          </div>
          <div>
            <dt>{{ t('dashboard.usagePeriod') }}</dt>
            <dd>{{ usage?.period ?? '—' }}</dd>
          </div>
          <div>
            <dt>{{ t('billing.openInvoices') }}</dt>
            <dd>{{ formatNumber(openInvoices.length) }}</dd>
          </div>
          <div>
            <dt>{{ t('billing.amount') }}</dt>
            <dd>{{ formatMicroEur(amountDueMicro) }}</dd>
          </div>
        </dl>
      </article>
    </div>

    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 6rem" /></div>

    <article v-else class="md-card fn-recent">
      <div class="fn-recent__head">
        <h2 class="em-section-title">{{ t('billing.invoicesTitle') }}</h2>
      </div>
      <EmptyState
        v-if="!invoiceItems.length"
        :title="t('billing.invoicesEmpty')"
        icon="receipt_long"
      />
      <template v-else>
        <div class="fn-table-wrap">
          <table class="fn-table">
            <thead>
              <tr>
                <th scope="col">{{ t('billing.invoiceId') }}</th>
                <th scope="col">{{ t('billing.colPeriod') }}</th>
                <th scope="col">{{ t('billing.amount') }}</th>
                <th scope="col">{{ t('billing.status') }}</th>
                <th scope="col">{{ t('billing.colDue') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="invoice in invoiceItems" :key="invoice.id">
                <td><strong>{{ invoice.id }}</strong></td>
                <td>{{ invoicePeriod(invoice) }}</td>
                <td>{{ formatMicroEur(invoice.amountDueMicroEur) }}</td>
                <td>
                  <span
                    class="fn-badge"
                    :class="invoiceStatus(invoice.status).tone ? `fn-badge--${invoiceStatus(invoice.status).tone}` : ''"
                  >
                    {{ invoiceStatus(invoice.status).label }}
                  </span>
                </td>
                <td>{{ invoiceDue(invoice) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="fn-table-foot">
          <span>{{ t('dashboard.recordCount', { count: invoiceItems.length }) }}</span>
        </div>
      </template>
    </article>
  </section>
</template>
