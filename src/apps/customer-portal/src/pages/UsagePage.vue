<script setup>
import { computed, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import StatCard from '../components/ui/StatCard.vue';
import { t } from '../i18n';
import { formatMicroEur, formatNumber } from '../utils/format';

const session = useSession();
const activeTab = ref('overview');

const tabs = [
  { id: 'overview', labelKey: 'usage.tabOverview' },
  { id: 'endpoint', labelKey: 'usage.tabEndpoint' },
  { id: 'taskType', labelKey: 'usage.tabTaskType' },
];

const { data: usage, loading: usageLoading } = useAsyncResource(
  () => portalApi.usage(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.billing:read')) },
);

const { data: tasks, loading: tasksLoading } = useAsyncResource(
  () => portalApi.tasks(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.tasks:read')) },
);

const loading = computed(() => usageLoading.value || tasksLoading.value);

const endpointStats = computed(() => {
  const items = tasks.value?.items ?? [];
  const counts = {};
  for (const task of items) {
    const key = `/v1/tasks/${task.taskType?.split('.')[0] ?? 'other'}`;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  const total = items.length || 1;
  return Object.entries(counts)
    .map(([endpoint, count]) => ({
      endpoint,
      count,
      pct: Math.round((count / total) * 1000) / 10,
    }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);
});

const taskTypeStats = computed(() => {
  const items = tasks.value?.items ?? [];
  const counts = {};
  for (const task of items) {
    counts[task.taskType] = (counts[task.taskType] ?? 0) + 1;
  }
  const total = items.length || 1;
  return Object.entries(counts)
    .map(([type, count]) => ({
      type,
      count,
      pct: Math.round((count / total) * 1000) / 10,
    }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 6);
});
</script>

<template>
  <section class="em-page">
    <div class="em-tabs" role="tablist">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        type="button"
        role="tab"
        class="em-tab"
        :class="{ 'em-tab--active': activeTab === tab.id }"
        :aria-selected="activeTab === tab.id"
        @click="activeTab = tab.id"
      >
        {{ t(tab.labelKey) }}
      </button>
    </div>

    <div v-if="loading" class="stat-grid">
      <div v-for="n in 4" :key="n" class="md-skeleton" style="height: 5rem" />
    </div>

    <template v-else>
      <div v-if="activeTab === 'overview'" class="stat-grid stat-grid--responsive">
        <StatCard
          :label="t('usage.totalRequests')"
          :value="formatNumber(usage?.taskCount ?? tasks?.items?.length ?? 0)"
          icon="api"
        />
        <StatCard
          :label="t('dashboard.usagePeriod')"
          :value="usage?.period ?? '—'"
          icon="calendar_month"
        />
        <StatCard
          :label="t('billing.compute')"
          :value="formatMicroEur(usage?.computeMicroEur)"
          icon="memory"
        />
        <StatCard
          :label="t('usage.activeTasks')"
          :value="formatNumber(tasks?.items?.length ?? 0)"
          icon="assignment"
        />
      </div>

      <article v-if="activeTab === 'endpoint'" class="md-card">
        <h2 class="em-section-title">{{ t('usage.topEndpoints') }}</h2>
        <div v-if="!endpointStats.length" class="empty-state">{{ t('usage.noData') }}</div>
        <ul v-else class="em-bar-list">
          <li v-for="row in endpointStats" :key="row.endpoint">
            <div class="em-bar-list__label">
              <code>{{ row.endpoint }}</code>
              <span>{{ formatNumber(row.count) }} ({{ row.pct }}%)</span>
            </div>
            <div class="em-bar-list__track">
              <div class="em-bar-list__fill" :style="{ width: `${row.pct}%` }" />
            </div>
          </li>
        </ul>
      </article>

      <article v-if="activeTab === 'taskType'" class="md-card">
        <h2 class="em-section-title">{{ t('usage.byTaskType') }}</h2>
        <div v-if="!taskTypeStats.length" class="empty-state">{{ t('usage.noData') }}</div>
        <ul v-else class="em-bar-list">
          <li v-for="row in taskTypeStats" :key="row.type">
            <div class="em-bar-list__label">
              <code>{{ row.type }}</code>
              <span>{{ formatNumber(row.count) }} ({{ row.pct }}%)</span>
            </div>
            <div class="em-bar-list__track">
              <div class="em-bar-list__fill em-bar-list__fill--alt" :style="{ width: `${row.pct}%` }" />
            </div>
          </li>
        </ul>
      </article>
    </template>
  </section>
</template>
