<script setup>
import { computed, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import StatCard from '../components/ui/StatCard.vue';
import UsageTrendChart from '../components/UsageTrendChart.vue';
import { t } from '../i18n';
import { formatMicroEur, formatNumber, taskStatusGroup } from '../utils/format';

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

const { data: balance, loading: balanceLoading } = useAsyncResource(
  () => portalApi.balance(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.billing:read')) },
);

const { data: tasks, loading: tasksLoading } = useAsyncResource(
  () => portalApi.tasks(session.workspaceId),
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.tasks:read')) },
);

const loading = computed(() => usageLoading.value || balanceLoading.value || tasksLoading.value);

const taskItems = computed(() => tasks.value?.items ?? []);

const usedMicro = computed(() => usage.value?.computeMicroEur ?? 0);
const limitMicro = computed(() => {
  const available = balance.value?.availableMicroEur ?? 0;
  const reserved = balance.value?.reservedMicroEur ?? 0;
  return Math.max(usedMicro.value + available + reserved, 1);
});
const usageRate = computed(() => {
  if (!usage.value && !balance.value) return '—';
  return `${Math.min(100, Math.round((usedMicro.value / limitMicro.value) * 100))}%`;
});
const requestCount = computed(() => usage.value?.taskCount ?? taskItems.value.length);
const averageMicro = computed(() => {
  if (!requestCount.value) return 0;
  return Math.round(usedMicro.value / requestCount.value);
});

const STATUS_ORDER = ['done', 'running', 'queued', 'cancel'];
const STATUS_LABELS = {
  done: 'tasks.statusDone',
  running: 'tasks.statusRunning',
  queued: 'tasks.statusQueued',
  cancel: 'tasks.statusCancel',
};

const statusStats = computed(() => {
  const counts = Object.fromEntries(STATUS_ORDER.map((status) => [status, 0]));
  for (const task of taskItems.value) {
    const group = taskStatusGroup(task.lifecycleStatus);
    if (group in counts) {
      counts[group] += 1;
    }
  }
  const total = taskItems.value.length || 1;
  return STATUS_ORDER.map((status) => ({
    status,
    label: t(STATUS_LABELS[status]),
    count: counts[status],
    pct: Math.round((counts[status] / total) * 1000) / 10,
  }));
});

const activeTaskCount = computed(
  () => statusStats.value.filter((row) => row.status === 'running' || row.status === 'queued')
    .reduce((sum, row) => sum + row.count, 0),
);

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
      <template v-if="activeTab === 'overview'">
        <div class="stat-grid stat-grid--responsive">
          <StatCard
            :label="t('usage.totalRequests')"
            :value="formatNumber(requestCount)"
            :hint="usage?.period ?? '—'"
            icon="api"
          />
          <StatCard
            :label="t('billing.compute')"
            :value="formatMicroEur(usedMicro)"
            :hint="`${t('usage.averageCost')}: ${formatMicroEur(averageMicro)}`"
            icon="memory"
          />
          <StatCard
            :label="t('dashboard.usageRate')"
            :value="usageRate"
            :hint="`${formatMicroEur(usedMicro)} / ${formatMicroEur(limitMicro)}`"
            icon="data_usage"
          />
          <StatCard
            :label="t('usage.activeTasks')"
            :value="formatNumber(activeTaskCount)"
            :hint="`${t('tasks.statusRunning')} ${formatNumber(statusStats.find((row) => row.status === 'running')?.count ?? 0)} · ${t('tasks.statusQueued')} ${formatNumber(statusStats.find((row) => row.status === 'queued')?.count ?? 0)}`"
            icon="assignment"
          />
        </div>

        <div class="em-layout-charts">
          <UsageTrendChart :task-items="taskItems" />

          <article class="md-card em-usage-details">
            <h2 class="em-section-title">{{ t('billing.usageSummary') }}</h2>
            <div class="em-usage-gauge__header">
              <span>{{ usage?.period ?? '—' }}</span>
              <strong>{{ usageRate }}</strong>
            </div>
            <div class="em-usage-gauge__track">
              <div class="em-usage-gauge__fill" :style="{ width: usageRate === '—' ? '0%' : usageRate }" />
            </div>
            <dl class="em-usage-details__list">
              <div>
                <dt>{{ t('billing.available') }}</dt>
                <dd>{{ formatMicroEur(balance?.availableMicroEur) }}</dd>
              </div>
              <div>
                <dt>{{ t('usage.reserved') }}</dt>
                <dd>{{ formatMicroEur(balance?.reservedMicroEur) }}</dd>
              </div>
              <div>
                <dt>{{ t('usage.averageCost') }}</dt>
                <dd>{{ formatMicroEur(averageMicro) }}</dd>
              </div>
              <div>
                <dt>{{ t('dashboard.usagePeriod') }}</dt>
                <dd>{{ usage?.period ?? '—' }}</dd>
              </div>
            </dl>
            <h3 class="em-usage-details__subtitle">{{ t('usage.statusBreakdown') }}</h3>
            <ul class="em-bar-list">
              <li v-for="row in statusStats" :key="row.status">
                <div class="em-bar-list__label">
                  <span>{{ row.label }}</span>
                  <span>{{ formatNumber(row.count) }} ({{ row.pct }}%)</span>
                </div>
                <div class="em-bar-list__track">
                  <div
                    class="em-bar-list__fill"
                    :class="`em-bar-list__fill--${row.status}`"
                    :style="{ width: `${row.pct}%` }"
                  />
                </div>
              </li>
            </ul>
          </article>
        </div>
      </template>

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
