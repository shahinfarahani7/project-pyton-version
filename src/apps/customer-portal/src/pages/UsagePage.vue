<script setup>
import { computed } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import StatCard from '../components/ui/StatCard.vue';
import UsageTrendChart from '../components/UsageTrendChart.vue';
import { t } from '../i18n';
import { formatMicroEur, formatNumber, taskStatusGroup } from '../utils/format';

const session = useSession();

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

const succeededCount = computed(
  () => taskItems.value.filter((task) => taskStatusGroup(task.lifecycleStatus) === 'done').length,
);

const familyStats = computed(() => {
  const counts = {};
  for (const task of taskItems.value) {
    const family = task.taskType?.split('.')[0] ?? 'other';
    counts[family] = (counts[family] ?? 0) + 1;
  }
  const total = taskItems.value.length || 1;
  const palette = ['#cdae6f', '#2c84ff', '#19c7b4', '#c0a064'];
  return Object.entries(counts)
    .map(([label, count], index) => ({
      label,
      count,
      pct: Math.round((count / total) * 1000) / 10,
      color: palette[index % palette.length],
    }))
    .sort((a, b) => b.count - a.count);
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
    <div v-if="loading" class="stat-grid stat-grid--responsive">
      <div v-for="n in 4" :key="n" class="md-skeleton" style="height: 5rem" />
    </div>

    <template v-else>
      <div class="stat-grid stat-grid--responsive">
        <StatCard
          :label="t('usage.totalRequests')"
          :value="formatNumber(requestCount)"
          :hint="usage?.period ?? '—'"
          icon="tasks"
        />
        <StatCard
          :label="t('billing.compute')"
          :value="formatMicroEur(usedMicro)"
          :hint="`${usageRate} · ${t('usage.averageCost')} ${formatMicroEur(averageMicro)}`"
          icon="wallet"
        />
        <StatCard
          :label="t('usage.activeTasks')"
          :value="formatNumber(activeTaskCount)"
          :hint="`${t('tasks.statusRunning')} ${formatNumber(statusStats.find((row) => row.status === 'running')?.count ?? 0)} · ${t('tasks.statusQueued')} ${formatNumber(statusStats.find((row) => row.status === 'queued')?.count ?? 0)}`"
          icon="clock"
        />
        <StatCard
          :label="t('tasks.statusDone')"
          :value="formatNumber(succeededCount)"
          :hint="usage?.period ?? '—'"
          icon="check"
        />
      </div>

      <div class="em-layout-charts">
        <UsageTrendChart :task-items="taskItems" />

        <article class="md-card em-usage-details">
          <h2 class="em-section-title">{{ t('dashboard.distribution') }}</h2>
          <div v-if="!familyStats.length" class="empty-state">{{ t('usage.noData') }}</div>
          <ul v-else class="em-bar-list">
            <li v-for="row in familyStats" :key="row.label">
              <div class="em-bar-list__label">
                <span>{{ row.label }}</span>
                <strong>{{ row.pct }}%</strong>
              </div>
              <div class="em-bar-list__track">
                <div class="em-bar-list__fill" :style="{ width: `${row.pct}%`, background: row.color }" />
              </div>
            </li>
          </ul>
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

      <article class="md-card">
        <h2 class="em-section-title">{{ t('usage.byTaskType') }}</h2>
        <div v-if="!taskTypeStats.length" class="empty-state">{{ t('usage.noData') }}</div>
        <div v-else class="md-table-wrap">
          <table class="md-table">
            <thead>
              <tr>
                <th scope="col">{{ t('usage.byTaskType') }}</th>
                <th scope="col">{{ t('dashboard.taskRuns') }}</th>
                <th scope="col">{{ t('billing.compute') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in taskTypeStats" :key="row.type">
                <td><code>{{ row.type }}</code></td>
                <td>{{ formatNumber(row.count) }}</td>
                <td>{{ row.pct }}%</td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
    </template>
  </section>
</template>
