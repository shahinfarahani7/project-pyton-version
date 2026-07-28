<script setup>
import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';

const session = useSession();

const { data: items, error, loading } = useAsyncResource(
  () => portalApi.disputes(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.billing:read')) },
);
</script>

<template>
  <section>
    <PageHeader :title="t('nav.disputes')" :subtitle="t('disputes.subtitle')">
      <template #actions>
        <button type="button" class="md-btn md-btn-filled" disabled>
          <span class="material-symbols-outlined" aria-hidden="true">report</span>
          {{ t('disputes.open') }}
        </button>
      </template>
    </PageHeader>
    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" /></div>
    <EmptyState
      v-else-if="!(items?.items?.length)"
      :title="t('disputes.emptyTitle')"
      icon="gavel"
    />
    <div v-else class="md-table-wrap">
      <table class="md-table">
        <thead>
          <tr>
            <th scope="col">{{ t('disputes.colId') }}</th>
            <th scope="col">{{ t('billing.status') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in items.items" :key="item.id">
            <td>{{ item.id }}</td>
            <td><StatusChip :status="item.status" /></td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
