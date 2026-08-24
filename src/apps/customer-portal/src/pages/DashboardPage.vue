<script setup>
import { computed, onMounted, ref } from 'vue';
import { RouterLink } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import StatCard from '../components/ui/StatCard.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import TaskResultCell from '../components/TaskResultCell.vue';
import UsageTrendChart from '../components/UsageTrendChart.vue';
import { t } from '../i18n';
import { formatDateTime, formatMicroEur, formatNumber, formatTaskType } from '../utils/format';
import { buildDonutGradient } from '../utils/chartHelpers';

const session = useSession();
const loading = ref(true);
const usage = ref(null);
const balance = ref(null);
const tasks = ref(null);

const taskItems = computed(() => tasks.value?.items ?? []);

const successCount = computed(() =>
  taskItems.value.filter((task) =>
    ['succeeded', 'completed'].includes(String(task.lifecycleStatus).toLowerCase()),
  ).length,
);

const failedCount = computed(() =>
  taskItems.value.filter((task) =>
    ['failed', 'rejected'].includes(String(task.lifecycleStatus).toLowerCase()),
  ).length,
);

const successRate = computed(() => {
  const total = taskItems.value.length;
  if (!total) return '—';
  return `${Math.round((successCount.value / total) * 1000) / 10}%`;
});

const distribution = computed(() => {
  const buckets = {};
  for (const task of taskItems.value) {
    const family = task.taskTypeMeta?.pipelineFamily ?? task.taskType?.split('.')[0] ?? 'other';
    buckets[family] = (buckets[family] ?? 0) + 1;
  }
  const total = taskItems.value.length || 1;
  const palette = ['#7c4dff', '#5b8def', '#34d399', '#fbbf24', '#94a3b8'];
  const slices = Object.entries(buckets)
    .map(([label, count], index) => ({
      label,
      count,
      pct: (count / total) * 100,
      color: palette[index % palette.length],
    }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);
  const pctTotal = slices.reduce((sum, slice) => sum + slice.pct, 0) || 1;
  return slices.map((slice) => ({
    ...slice,
    pct: Math.round((slice.pct / pctTotal) * 1000) / 10,
  }));
});

const donutGradient = computed(() => buildDonutGradient(distribution.value));

onMounted(() => {
  if (!session.workspaceId) {
    loading.value = false;
    return;
  }
  void Promise.all([
    portalApi.usage(session.workspaceId).then((body) => {
      usage.value = body;
    }),
    portalApi.balance(session.workspaceId).then((body) => {
      balance.value = body;
    }),
    session.hasPermission('customer.tasks:read')
      ? portalApi.tasks(session.workspaceId).then((body) => {
          tasks.value = body;
        })
      : Promise.resolve(),
  ]).finally(() => {
    loading.value = false;
  });
});
</script>

<template>
  <section class="em-page">
    <div class="em-status-pill em-status-pill--success em-status-pill--banner">
      <span class="material-symbols-outlined" aria-hidden="true">verified</span>
      {{ t('dashboard.systemsOperational') }}
    </div>

    <div v-if="loading" class="stat-grid stat-grid--responsive">
      <div v-for="n in 4" :key="n" class="md-skeleton" style="height: 5.5rem" />
    </div>
    <div v-else class="stat-grid stat-grid--responsive">
      <StatCard
        :label="t('dashboard.totalTasks')"
        :value="formatNumber(taskItems.length)"
        :hint="usage?.period ?? '—'"
        icon="assignment"
      />
      <StatCard
        :label="t('dashboard.successRate')"
        :value="successRate"
        :hint="`${formatNumber(successCount)} ${t('tasks.statusCompleted').toLowerCase()}`"
        icon="task_alt"
      />
      <StatCard
        :label="t('dashboard.failedRejected')"
        :value="formatNumber(failedCount)"
        icon="error"
      />
      <StatCard
        :label="t('dashboard.balance')"
        :value="formatMicroEur(balance?.availableMicroEur)"
        icon="schedule"
      />
    </div>

    <div class="em-layout-charts">
      <UsageTrendChart :task-items="taskItems" />

      <article class="md-card em-chart-card">
        <h2 class="em-section-title">{{ t('dashboard.distribution') }}</h2>
        <div v-if="!distribution.length" class="empty-state">{{ t('usage.noData') }}</div>
        <div v-else class="em-donut-layout">
          <div
            class="em-donut-ring"
            role="img"
            :aria-label="t('dashboard.distribution')"
            :style="{ background: donutGradient }"
          />
          <ul class="em-donut-legend">
            <li v-for="slice in distribution" :key="slice.label">
              <span class="em-donut-legend__dot" :style="{ background: slice.color }" />
              <span>{{ slice.label }}</span>
              <strong>{{ slice.pct }}%</strong>
            </li>
          </ul>
        </div>
      </article>
    </div>

    <div class="em-layout-dashboard-bottom">
      <article v-if="taskItems.length" class="md-card">
        <div class="em-section-header">
          <h2 class="em-section-title">{{ t('dashboard.recentTasks') }}</h2>
          <RouterLink class="md-btn md-btn-text" :to="{ name: 'tasks' }">{{ t('tasks.viewAll') }}</RouterLink>
        </div>
        <ul class="em-task-list">
          <li v-for="task in taskItems.slice(0, 5)" :key="task.id">
            <RouterLink :to="{ name: 'task-detail', params: { id: task.id } }" class="em-task-row">
              <div class="em-task-row__primary">
                <code class="em-task-row__id">{{ task.id.slice(0, 8) }}</code>
                <p class="em-task-row__type">{{ formatTaskType(task) }}</p>
              </div>
              <TaskResultCell :task="task" />
              <div class="em-task-row__meta">
                <StatusChip :status="task.lifecycleStatus" />
                <span>{{ formatDateTime(task.createdAt) }}</span>
              </div>
            </RouterLink>
          </li>
        </ul>
      </article>
      <article class="md-card em-session-strip">
        <dl class="em-kv-list">
          <div>
            <dt>{{ t('dashboard.workspaceId') }}</dt>
            <dd><code>{{ session.workspaceId }}</code></dd>
          </div>
          <div>
            <dt>{{ t('dashboard.sessionId') }}</dt>
            <dd><code>{{ session.sessionPublicId }}</code></dd>
          </div>
        </dl>
      </article>
    </div>
  </section>
</template>
