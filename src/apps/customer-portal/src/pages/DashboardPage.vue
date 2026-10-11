<script setup>
import { computed, onMounted, ref } from 'vue';
import { RouterLink } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import StatCard from '../components/ui/StatCard.vue';
import StrokeIcon from '../components/ui/StrokeIcon.vue';
import UsageTrendChart from '../components/UsageTrendChart.vue';
import { t } from '../i18n';
import { formatDateTime, formatMicroEur, formatNumber, taskListTitle, taskStatusGroup } from '../utils/format';

const session = useSession();
const loading = ref(true);
const usage = ref(null);
const balance = ref(null);
const tasks = ref(null);

const taskItems = computed(() => tasks.value?.items ?? []);

const succeededCount = computed(
  () => taskItems.value.filter((task) => taskStatusGroup(task.lifecycleStatus) === 'done').length,
);
const failedCount = computed(
  () => taskItems.value.filter((task) => taskStatusGroup(task.lifecycleStatus) === 'failed').length,
);
const successRate = computed(() => {
  if (!taskItems.value.length) {
    return '—';
  }
  return `${Math.round((succeededCount.value / taskItems.value.length) * 1000) / 10}%`;
});

const distribution = computed(() => {
  const buckets = {};
  for (const task of taskItems.value) {
    const family = task.taskTypeMeta?.pipelineFamily ?? task.taskType?.split('.')[0] ?? 'other';
    buckets[family] = (buckets[family] ?? 0) + 1;
  }
  const total = taskItems.value.length || 1;
  const palette = ['#cdae6f', '#2c84ff', '#19c7b4', '#c0a064', '#b3b5bd'];
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

const recentTasks = computed(() => taskItems.value.slice(0, 5));

function statusPresentation(status) {
  const group = taskStatusGroup(status);
  if (group === 'done') return { label: t('dashboard.statusSucceeded'), tone: '' };
  if (group === 'running') return { label: t('dashboard.statusRunning'), tone: 'blue' };
  if (group === 'queued') return { label: t('dashboard.statusQueued'), tone: 'warn' };
  if (group === 'failed') return { label: t('dashboard.statusFailed'), tone: 'bad' };
  if (group === 'cancel') return { label: t('dashboard.statusCancelled'), tone: 'neutral' };
  return { label: String(status || '—'), tone: 'neutral' };
}

function taskDuration(task) {
  const group = taskStatusGroup(task?.lifecycleStatus);
  if (group === 'queued' || group === 'running') return '—';
  const start = Date.parse(task?.createdAt ?? '');
  const end = Date.parse(task?.updatedAt ?? '');
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return '—';
  const seconds = (end - start) / 1000;
  if (seconds < 60) return `${(Math.round(seconds * 10) / 10).toFixed(1)}s`;
  const minutes = Math.floor(seconds / 60);
  const rest = Math.round(seconds % 60);
  return `${minutes}m ${rest}s`;
}

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
    <section class="fn-hero">
      <div class="fn-hero__copy">
        <p class="fn-eyebrow">{{ t('dashboard.heroTag') }}</p>
        <h2>{{ t('dashboard.heroTitle') }}</h2>
        <p>{{ t('dashboard.heroBody') }}</p>
        <RouterLink class="md-btn md-btn-filled" :to="{ name: 'tasks' }">
          <StrokeIcon name="plus" />
          {{ t('dashboard.createTask') }}
        </RouterLink>
      </div>
      <div class="fn-hero__net" aria-hidden="true">
        <span /><span /><span /><span /><span /><span />
      </div>
    </section>

    <div v-if="loading" class="stat-grid stat-grid--responsive stat-grid--dashboard">
      <div v-for="n in 4" :key="n" class="md-skeleton" style="height: 5.5rem" />
    </div>
    <div v-else class="stat-grid stat-grid--responsive stat-grid--dashboard">
      <StatCard
        :label="t('dashboard.totalTasks')"
        :value="formatNumber(taskItems.length)"
        :hint="usage?.period ?? '—'"
        icon="tasks"
      />
      <StatCard
        :label="t('dashboard.successRate')"
        :value="successRate"
        :hint="`${formatNumber(succeededCount)} ${t('dashboard.loadedTasks')}`"
        icon="check"
      />
      <StatCard
        :label="t('dashboard.failedTasks')"
        :value="formatNumber(failedCount)"
        :hint="t('dashboard.loadedTasks')"
        icon="alert"
      />
      <StatCard
        :label="t('dashboard.balance')"
        :value="formatMicroEur(balance?.availableMicroEur)"
        :hint="`${t('dashboard.reserved')} ${formatMicroEur(balance?.reservedMicroEur)}`"
        icon="wallet"
      />
    </div>

    <div class="em-layout-charts">
      <UsageTrendChart variant="bar" :task-items="taskItems" />

      <article class="md-card em-chart-card">
        <h2 class="em-section-title">{{ t('dashboard.distribution') }}</h2>
        <div v-if="!distribution.length" class="empty-state">{{ t('usage.noData') }}</div>
        <ul v-else class="em-bar-list">
          <li v-for="slice in distribution" :key="slice.label">
            <div class="em-bar-list__label">
              <span>{{ slice.label }}</span>
              <strong>{{ slice.pct }}%</strong>
            </div>
            <div class="em-bar-list__track">
              <div class="em-bar-list__fill" :style="{ width: `${slice.pct}%`, background: slice.color }" />
            </div>
          </li>
        </ul>
      </article>
    </div>

    <article v-if="recentTasks.length" class="md-card fn-recent">
      <div class="fn-recent__head">
        <h2 class="em-section-title">{{ t('dashboard.recentTasks') }}</h2>
        <RouterLink class="md-btn md-btn-text" :to="{ name: 'tasks' }">
          {{ t('dashboard.viewAllTasks') }}
          <StrokeIcon name="arrow" />
        </RouterLink>
      </div>
      <div class="fn-table-wrap">
        <table class="fn-table">
          <thead>
            <tr>
              <th scope="col">{{ t('tasks.colId') }}</th>
              <th scope="col">{{ t('dashboard.colRequest') }}</th>
              <th scope="col">{{ t('tasks.colType') }}</th>
              <th scope="col">{{ t('dashboard.colStatus') }}</th>
              <th scope="col">{{ t('tasks.colCreated') }}</th>
              <th scope="col">{{ t('dashboard.colDuration') }}</th>
              <th scope="col"><span class="fn-table__muted">{{ t('dashboard.colOpen') }}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="task in recentTasks" :key="task.id">
              <td><strong>{{ task.id }}</strong></td>
              <td>{{ taskListTitle(task) }}</td>
              <td>{{ task.taskType || '—' }}</td>
              <td>
                <span class="fn-badge" :class="statusPresentation(task.lifecycleStatus).tone ? `fn-badge--${statusPresentation(task.lifecycleStatus).tone}` : ''">
                  {{ statusPresentation(task.lifecycleStatus).label }}
                </span>
              </td>
              <td>{{ formatDateTime(task.createdAt) }}</td>
              <td>{{ taskDuration(task) }}</td>
              <td>
                <RouterLink
                  class="fn-table__open"
                  :to="{ name: 'task-detail', params: { id: task.id } }"
                  :aria-label="`${t('dashboard.colOpen')} ${task.id}`"
                >
                  <StrokeIcon name="arrow" />
                </RouterLink>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="fn-table-foot">
        <span>{{ t('dashboard.recordCount', { count: recentTasks.length }) }}</span>
      </div>
    </article>
  </section>
</template>
