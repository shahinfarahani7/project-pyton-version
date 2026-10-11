<script setup>
import { computed, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
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

const loading = computed(() => walletsLoading.value || usageLoading.value);
const walletItems = computed(() => wallets.value?.items ?? []);
const availableMicro = computed(() =>
  walletItems.value.reduce((sum, wallet) => sum + wholeMicro(wallet.availableMicroEur), 0),
);
const reservedMicro = computed(() =>
  walletItems.value.reduce((sum, wallet) => sum + wholeMicro(wallet.reservedMicroEur), 0),
);
const usedMicro = computed(() => wholeMicro(usage.value?.computeMicroEur));

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
  <section class="em-page">
    <div v-if="loading" class="fn-wallet-summary">
      <div v-for="n in 2" :key="n" class="md-skeleton" style="height: 8rem" />
    </div>
    <template v-else>
      <div class="fn-wallet-summary">
        <article class="md-card fn-balance-card">
          <p class="fn-section-caption">{{ t('wallet.availableCompute') }}</p>
          <p class="fn-money">{{ formatMicroEur(availableMicro) }}</p>
          <div class="fn-balance-details">
            <span>
              <StrokeIcon name="lock" />
              {{ formatMicroEur(reservedMicro) }} {{ t('wallet.reservedWord') }}
            </span>
            <span>{{ formatNumber(walletItems.length) }} {{ t('wallet.count') }}</span>
          </div>
        </article>
        <article class="md-card">
          <div class="fn-card-head">
            <h2 class="em-section-title">{{ t('wallet.creditUsage') }}</h2>
            <span v-if="usage?.period" class="fn-badge fn-badge--neutral">{{ usage.period }}</span>
          </div>
          <dl class="fn-kv">
            <div>
              <dt>{{ t('billing.compute') }}</dt>
              <dd>{{ formatMicroEur(usedMicro) }}</dd>
            </div>
            <div>
              <dt>{{ t('wallet.reservedCredit') }}</dt>
              <dd>{{ formatMicroEur(reservedMicro) }}</dd>
            </div>
            <div>
              <dt>{{ t('billing.currency') }}</dt>
              <dd>EUR</dd>
            </div>
          </dl>
          <p class="fn-wallet-note">{{ t('wallet.separate') }}</p>
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
      <p class="fn-notice">
        <StrokeIcon name="wallet" />
        <span>{{ t('wallet.notice') }}</span>
      </p>
    </template>
  </section>
</template>
