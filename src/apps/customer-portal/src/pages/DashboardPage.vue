<script setup>
import { computed, onMounted, ref } from 'vue';
import { RouterLink } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import StatCard from '../components/ui/StatCard.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import TaskResultCell from '../components/TaskResultCell.vue';
import { t } from '../i18n';
import { formatDateTime, formatMicroEur, formatNumber, formatTaskType } from '../utils/format';

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
  return Object.entries(buckets)
    .map(([label, count], index) => ({
      label,
      count,
      pct: Math.round((count / total) * 1000) / 10,
      color: palette[index % palette.length],
    }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);
});

const donutSegments = computed(() => {
  let offset = 0;
  const circumference = 2 * Math.PI * 42;
  return distribution.value.map((slice) => {
    const dash = (slice.pct / 100) * circumference;
    const segment = { ...slice, dash, offset, circumference };
    offset += dash;
    return segment;
  });
});

const trendPoints = computed(() => {
  const counts = [3, 5, 4, 7, 6, 8, taskItems.value.length || 5];
  const max = Math.max(...counts, 1);
  return counts
    .map((value, index) => {
      const x = 20 + index * 40;
      const y = 90 - (value / max) * 70;
      return `${x},${y}`;
    })
    .join(' ');
});

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
      <article class="md-card em-chart-card">
        <h2 class="em-section-title">{{ t('dashboard.usageTrend') }}</h2>
        <svg class="em-line-chart" viewBox="0 0 260 100" role="img" :aria-label="t('dashboard.usageTrend')">
          <polyline class="em-line-chart__grid" points="0,90 260,90" />
          <polyline class="em-line-chart__line" :points="trendPoints" />
        </svg>
      </article>

      <article class="md-card em-chart-card">
        <h2 class="em-section-title">{{ t('dashboard.distribution') }}</h2>
        <div class="em-donut-layout">
          <svg class="em-donut" viewBox="0 0 100 100" role="img" :aria-label="t('dashboard.distribution')">
            <circle cx="50" cy="50" r="42" class="em-donut__track" />
            <circle
              v-for="(segment, index) in donutSegments"
              :key="segment.label"
              cx="50"
              cy="50"
              r="42"
              class="em-donut__segment"
              :stroke="segment.color"
              :stroke-dasharray="`${segment.dash} ${segment.circumference}`"
              :stroke-dashoffset="-donutSegments.slice(0, index).reduce((sum, s) => sum + s.dash, 0)"
            />
          </svg>
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
