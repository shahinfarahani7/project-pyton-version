<script setup>
import { computed, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
import StrokeIcon from '../components/ui/StrokeIcon.vue';
import { t } from '../i18n';
import { formatMicroEur, formatNumber } from '../utils/format';

const session = useSession();
const walletName = ref('');
const walletAmount = ref(10);
const adding = ref(false);
const formOpen = ref(false);
const addError = ref('');

function wholeMicro(value) {
  return Number.isInteger(value) ? value : 0;
}

const canReadBilling = () =>
  Boolean(session.workspaceId && session.hasPermission('customer.billing:read'));

async function loadWallets() {
  try {
    return await portalApi.wallets(session.workspaceId);
  } catch {
    const balance = await portalApi.balance(session.workspaceId);
    return {
      items: [
        {
          id: 'wal_primary',
          name: 'Primary',
          availableMicroEur: balance?.availableMicroEur ?? 0,
          reservedMicroEur: balance?.reservedMicroEur ?? 0,
          builtin: true,
        },
      ],
    };
  }
}

const { data: wallets, loading: walletsLoading, refresh } = useAsyncResource(loadWallets, {
  enabled: canReadBilling,
});

const { data: usage, loading: usageLoading } = useAsyncResource(
  () => portalApi.usage(session.workspaceId),
  { enabled: canReadBilling },
);

const { data: invoices, loading: invoicesLoading } = useAsyncResource(
  () => portalApi.invoices(session.workspaceId),
  { enabled: canReadBilling },
);

const loading = computed(
  () => walletsLoading.value || usageLoading.value || invoicesLoading.value,
);

const walletItems = computed(() => wallets.value?.items ?? []);
const availableMicro = computed(() =>
  walletItems.value.reduce((sum, wallet) => sum + wholeMicro(wallet.availableMicroEur), 0),
);
const reservedMicro = computed(() =>
  walletItems.value.reduce((sum, wallet) => sum + wholeMicro(wallet.reservedMicroEur), 0),
);
const usedMicro = computed(() => wholeMicro(usage.value?.computeMicroEur));
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

function walletLabel(wallet) {
  return wallet.builtin ? t('wallet.primary') : wallet.name;
}

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

async function addWallet() {
  const name = walletName.value.trim();
  const euros = Number(walletAmount.value);
  if (!name || !Number.isInteger(euros) || euros <= 0 || !canReadBilling()) {
    addError.value = t('wallet.addError');
    return;
  }
  adding.value = true;
  addError.value = '';
  try {
    const created = await portalApi.addWallet(session.workspaceId, {
      name,
      amountMicroEur: euros * 1_000_000,
    });
    const current = wallets.value?.items ?? [];
    const next = current.some((wallet) => wallet.id === created.id)
      ? current.map((wallet) => ({ ...wallet }))
      : [...current.map((wallet) => ({ ...wallet })), created];
    wallets.value = { items: next };
    walletName.value = '';
    formOpen.value = false;
    await refresh({ silent: true });
  } catch (err) {
    addError.value = err?.message || t('wallet.addError');
  } finally {
    adding.value = false;
  }
}
</script>

<template>
  <section class="em-page em-page--billing">
    <div v-if="loading" class="fn-billing-grid">
      <div v-for="n in 2" :key="n" class="md-skeleton" style="height: 8rem" />
    </div>

    <template v-else>
      <div class="fn-billing-grid">
        <article class="md-card fn-balance-card">
          <div class="fn-card-head">
            <h2 class="em-section-title">{{ t('billing.available') }}</h2>
          </div>
          <p class="fn-money">{{ formatMicroEur(availableMicro) }}</p>
          <p class="fn-card-note">{{ t('billing.availableHint') }}</p>
          <dl class="fn-kv">
            <div>
              <dt>{{ t('dashboard.reserved') }}</dt>
              <dd>{{ formatMicroEur(reservedMicro) }}</dd>
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

      <div class="fn-wallet-head">
        <h2 class="em-section-title">{{ t('wallet.yourWallets') }}</h2>
        <button v-if="!formOpen" type="button" class="md-btn md-btn-filled" @click="formOpen = true">
          <StrokeIcon name="plus" />
          {{ t('wallet.add') }}
        </button>
      </div>
      <form v-if="formOpen" class="em-wallet-form md-card" @submit.prevent="addWallet">
        <label>
          <span>{{ t('wallet.name') }}</span>
          <input v-model="walletName" class="md-input" type="text" maxlength="80" required />
        </label>
        <label>
          <span>{{ t('wallet.amount') }}</span>
          <input v-model.number="walletAmount" class="md-input" type="number" min="1" step="1" max="1000000" required />
        </label>
        <div class="fn-wallet-form__actions">
          <button type="button" class="md-btn" @click="formOpen = false">{{ t('wallet.cancel') }}</button>
          <button type="submit" class="md-btn md-btn-filled" :disabled="adding">{{ t('wallet.add') }}</button>
        </div>
        <p v-if="addError" class="md-alert md-alert--error" role="alert">{{ addError }}</p>
      </form>
      <div class="fn-wallet-grid">
        <article v-for="wallet in walletItems" :key="wallet.id" class="md-card fn-wallet-tile">
          <div class="fn-card-head">
            <span class="fn-step-icon" aria-hidden="true"><StrokeIcon name="wallet" /></span>
            <span class="fn-badge fn-badge--neutral">{{ wallet.builtin ? t('wallet.primary') : t('wallet.custom') }}</span>
          </div>
          <h2>{{ walletLabel(wallet) }}</h2>
          <p class="fn-wallet-amount">{{ formatMicroEur(wallet.availableMicroEur) }}</p>
          <p class="fn-card-note">{{ t('billing.available') }}</p>
          <dl class="fn-kv">
            <div>
              <dt>{{ t('dashboard.reserved') }}</dt>
              <dd>{{ formatMicroEur(wallet.reservedMicroEur) }}</dd>
            </div>
            <div>
              <dt>{{ t('wallet.walletId') }}</dt>
              <dd><code>{{ wallet.id }}</code></dd>
            </div>
          </dl>
        </article>
      </div>

      <article class="md-card fn-recent">
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
    </template>
  </section>
</template>
