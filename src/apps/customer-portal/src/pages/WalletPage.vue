<script setup>
import { computed, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import StatCard from '../components/ui/StatCard.vue';
import { useAsyncResource } from '../composables/useAsyncResource';
import { t } from '../i18n';
import { formatMicroEur, formatNumber } from '../utils/format';

const session = useSession();
const walletName = ref('');
const walletAmount = ref(10);
const adding = ref(false);
const addError = ref('');

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

const loading = computed(() => walletsLoading.value || usageLoading.value);
const walletItems = computed(() => wallets.value?.items ?? []);
const availableMicro = computed(() =>
  walletItems.value.reduce((sum, wallet) => sum + (wallet.availableMicroEur ?? 0), 0),
);
const reservedMicro = computed(() =>
  walletItems.value.reduce((sum, wallet) => sum + (wallet.reservedMicroEur ?? 0), 0),
);
const usedMicro = computed(() => usage.value?.computeMicroEur ?? 0);
const limitMicro = computed(() => Math.max(usedMicro.value + availableMicro.value + reservedMicro.value, 1));
const usagePct = computed(() => {
  if (!usage.value && !wallets.value) return 0;
  return Math.min(100, Math.round((usedMicro.value / limitMicro.value) * 100));
});

function walletLabel(wallet) {
  return wallet.builtin ? t('wallet.primary') : wallet.name;
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
    await refresh({ silent: true });
  } catch (err) {
    addError.value = err?.message || t('wallet.addError');
  } finally {
    adding.value = false;
  }
}
</script>

<template>
  <section class="em-page">
    <div v-if="loading" class="stat-grid stat-grid--responsive stat-grid--dashboard">
      <div v-for="n in 3" :key="n" class="md-skeleton" style="height: 5.5rem" />
    </div>
    <template v-else>
      <div class="stat-grid stat-grid--responsive stat-grid--dashboard">
        <StatCard
          :label="t('billing.available')"
          :value="formatMicroEur(availableMicro)"
          icon="account_balance_wallet"
        />
        <StatCard
          :label="t('usage.reserved')"
          :value="formatMicroEur(reservedMicro)"
          icon="lock"
        />
        <StatCard
          :label="t('billing.compute')"
          :value="formatMicroEur(usedMicro)"
          :hint="usage?.period ?? '—'"
          icon="payments"
        />
      </div>

      <article class="md-card">
        <h2 class="em-section-title">{{ t('wallet.list') }}</h2>
        <ul class="em-invoice-list">
          <li v-for="wallet in walletItems" :key="wallet.id">
            <strong>{{ walletLabel(wallet) }}</strong>
            <span>{{ formatMicroEur(wallet.availableMicroEur) }}</span>
          </li>
        </ul>
        <form class="em-wallet-form" @submit.prevent="addWallet">
          <label>
            <span>{{ t('wallet.name') }}</span>
            <input v-model="walletName" class="md-input" type="text" maxlength="80" required />
          </label>
          <label>
            <span>{{ t('wallet.amount') }}</span>
            <input v-model.number="walletAmount" class="md-input" type="number" min="1" step="1" required />
          </label>
          <button type="button" class="md-btn md-btn-filled" :disabled="adding" @click="addWallet">
            {{ t('wallet.add') }}
          </button>
        </form>
        <p v-if="addError" class="md-alert md-alert--error" role="alert">{{ addError }}</p>
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
    </template>
  </section>
</template>
