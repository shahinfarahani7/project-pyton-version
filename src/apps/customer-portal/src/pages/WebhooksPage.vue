<script setup>
import { ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import EmptyState from '../components/ui/EmptyState.vue';
import { t } from '../i18n';

const session = useSession();

const webhookEvents = ref([
  { id: 'task.completed', labelKey: 'webhooks.eventCompleted', enabled: true, url: 'https://api.example.com/hooks/tasks' },
  { id: 'task.failed', labelKey: 'webhooks.eventFailed', enabled: true, url: 'https://api.example.com/hooks/failures' },
  { id: 'billing.alert', labelKey: 'webhooks.eventBilling', enabled: false, url: '' },
]);

const { data: items, error, loading } = useAsyncResource(() => portalApi.webhooks(), {
  enabled: () => session.hasPermission('customer.webhooks:read'),
});

const slaRows = [
  { metricKey: 'webhooks.slaResponse', actual: '1.28s', target: '< 2.0s', ok: true },
  { metricKey: 'webhooks.slaSuccess', actual: '96.3%', target: '> 99.0%', ok: false },
  { metricKey: 'webhooks.slaAvailability', actual: '100.0%', target: '> 99.9%', ok: true },
  { metricKey: 'webhooks.slaError', actual: '0.8%', target: '< 1.0%', ok: true },
];
</script>

<template>
  <section class="em-page em-page--webhooks">
    <button type="button" class="md-btn md-btn-filled md-btn-block em-action-top" disabled>
      <span class="material-symbols-outlined" aria-hidden="true">add_link</span>
      {{ t('webhooks.add') }}
    </button>
    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>

    <div class="em-layout-webhooks">
    <article class="md-card">
      <h2 class="em-section-title">{{ t('webhooks.settingsTitle') }}</h2>
      <ul class="em-webhook-list">
        <li v-for="event in webhookEvents" :key="event.id" class="em-webhook-item">
          <label class="em-toggle">
            <input v-model="event.enabled" type="checkbox" disabled />
            <span class="em-toggle__slider" />
          </label>
          <div class="em-webhook-item__body">
            <strong>{{ t(event.labelKey) }}</strong>
            <input
              class="md-input"
              type="url"
              :value="event.url"
              :placeholder="t('webhooks.urlPlaceholder')"
              disabled
            />
          </div>
        </li>
      </ul>
    </article>

    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 4rem" /></div>
    <article v-else-if="items?.items?.length" class="md-card">
      <h2 class="em-section-title">{{ t('webhooks.configuredTitle') }}</h2>
      <ul class="em-endpoint-list">
        <li v-for="item in items.items" :key="item.id">
          <code>{{ item.id }}</code>
          <span class="md-chip md-chip--neutral">{{ item.status }}</span>
        </li>
      </ul>
    </article>
    <EmptyState
      v-else
      :title="t('webhooks.emptyTitle')"
      icon="webhook"
    />

    <article class="md-card em-sla-card">
      <div class="em-sla-card__header">
        <span class="em-status-pill em-status-pill--success">
          <span class="material-symbols-outlined" aria-hidden="true">check_circle</span>
          {{ t('more.systemsOperational') }}
        </span>
      </div>
      <div class="em-sla-metrics">
        <div><span>{{ t('more.slaUptime') }}</span><strong>100.0%</strong></div>
        <div><span>{{ t('more.fallbackRate') }}</span><strong>0.15%</strong></div>
        <div><span>{{ t('more.cloudFallback') }}</span><strong>12</strong></div>
      </div>
      <div class="md-table-wrap">
        <table class="md-table em-sla-table">
          <thead>
            <tr>
              <th scope="col">{{ t('webhooks.metric') }}</th>
              <th scope="col">{{ t('webhooks.actual') }}</th>
              <th scope="col">{{ t('webhooks.target') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in slaRows" :key="row.metricKey">
              <td>{{ t(row.metricKey) }}</td>
              <td :class="row.ok ? 'em-sla-ok' : 'em-sla-warn'">{{ row.actual }}</td>
              <td>{{ row.target }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
    </div>
  </section>
</template>
