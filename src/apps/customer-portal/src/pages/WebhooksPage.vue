<script setup>
import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';

const session = useSession();

const { data: items, error, loading } = useAsyncResource(() => portalApi.webhooks(), {
  enabled: () => session.hasPermission('customer.webhooks:read'),
});
</script>

<template>
  <section>
    <PageHeader :title="t('nav.webhooks')" :subtitle="t('webhooks.subtitle')">
      <template #actions>
        <button type="button" class="md-btn md-btn-filled" disabled>
          <span class="material-symbols-outlined" aria-hidden="true">add_link</span>
          {{ t('webhooks.add') }}
        </button>
      </template>
    </PageHeader>
    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" /></div>
    <EmptyState
      v-else-if="!(items?.items?.length)"
      :title="t('webhooks.emptyTitle')"
      icon="webhook"
    />
    <div v-else class="md-table-wrap">
      <table class="md-table">
        <thead>
          <tr>
            <th scope="col">{{ t('webhooks.endpoint') }}</th>
            <th scope="col">{{ t('billing.status') }}</th>
            <th scope="col">{{ t('tasks.colVersion') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in items.items" :key="item.id">
            <td><code>{{ item.id }}</code></td>
            <td><StatusChip :status="item.status" /></td>
            <td>{{ item.version }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
