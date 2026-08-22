<script setup>
import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';

const session = useSession();

const { data: items, error, loading } = useAsyncResource(() => portalApi.apiKeys(), {
  enabled: () => session.hasPermission('customer.apikeys:read'),
});

function envTone(index) {
  const tones = ['production', 'testing', 'development'];
  return tones[index % tones.length];
}
</script>

<template>
  <section class="em-page">
    <button type="button" class="md-btn md-btn-filled md-btn-block" disabled>
      <span class="material-symbols-outlined" aria-hidden="true">key</span>
      {{ t('apiKeys.create') }}
    </button>
    <p class="login-note">{{ t('apiKeys.secretNote') }}</p>
    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 6rem" /></div>
    <EmptyState v-else-if="!(items?.items?.length)" :title="t('apiKeys.emptyTitle')" icon="key" />
    <ul v-else class="em-key-list">
      <li v-for="(item, index) in items.items" :key="item.id" class="md-card em-key-card">
        <div class="em-key-card__header">
          <span class="em-env-badge" :class="`em-env-badge--${envTone(index)}`">
            {{ t(`apiKeys.env.${envTone(index)}`) }}
          </span>
          <StatusChip :status="item.status" />
        </div>
        <code class="em-key-card__value">{{ item.id.slice(0, 8) }}••••••••{{ item.id.slice(-4) }}</code>
        <p class="md-hint">{{ t('apiKeys.keyId') }}: {{ item.id }}</p>
        <p class="md-hint">{{ t('tasks.colVersion') }}: {{ item.version }}</p>
      </li>
    </ul>
  </section>
</template>
