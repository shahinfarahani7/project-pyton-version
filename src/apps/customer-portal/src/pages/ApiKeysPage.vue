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
</script>

<template>
  <section class="em-page">
    <p class="fn-notice">
      <span class="material-symbols-outlined" aria-hidden="true">lock</span>
      <span>{{ t('apiKeys.secretNote') }}</span>
    </p>
    <div class="fn-toolbar">
      <button type="button" class="md-btn md-btn-filled" disabled>
        <span class="material-symbols-outlined" aria-hidden="true">key</span>
        {{ t('apiKeys.create') }}
      </button>
    </div>
    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 6rem" /></div>
    <EmptyState v-else-if="!(items?.items?.length)" :title="t('apiKeys.emptyTitle')" icon="key" />
    <div v-else class="fn-tilegrid">
      <article v-for="item in items.items" :key="item.id" class="md-card fn-tile">
        <div class="fn-tile__icon" aria-hidden="true">
          <span class="material-symbols-outlined">key</span>
        </div>
        <StatusChip :status="item.status" />
        <code class="em-key-card__value">{{ item.id.slice(0, 8) }}••••••••{{ item.id.slice(-4) }}</code>
        <dl class="em-kv-list">
          <div>
            <dt>{{ t('apiKeys.keyId') }}</dt>
            <dd><code>{{ item.id }}</code></dd>
          </div>
          <div>
            <dt>{{ t('tasks.colVersion') }}</dt>
            <dd>{{ item.version }}</dd>
          </div>
        </dl>
      </article>
    </div>
  </section>
</template>
