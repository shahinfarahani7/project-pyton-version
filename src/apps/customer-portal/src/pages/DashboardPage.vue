<script setup>
import { onMounted, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import PageHeader from '../components/ui/PageHeader.vue';
import StatCard from '../components/ui/StatCard.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';
import { formatMicroEur, formatNumber, formatDateTime } from '../utils/format';

const session = useSession();
const loading = ref(true);
const usage = ref(null);
const balance = ref(null);
const tasks = ref(null);
const principal = ref(null);

onMounted(() => {
  if (!session.workspaceId) {
    loading.value = false;
    return;
  }
  void Promise.all([
    portalApi.currentPrincipal().then((body) => {
      principal.value = body;
    }),
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
  <section>
    <PageHeader
      :title="t('dashboard.title')"
      :subtitle="t('dashboard.subtitle')"
    />
    <div v-if="loading" class="stat-grid">
      <div v-for="n in 4" :key="n" class="md-skeleton" />
    </div>
    <div v-else class="stat-grid">
      <StatCard
        :label="t('dashboard.tasks')"
        :value="formatNumber(tasks?.items?.length ?? 0)"
        icon="assignment"
      />
      <StatCard
        :label="t('dashboard.usagePeriod')"
        :value="usage?.period ?? '—'"
        :hint="`${formatNumber(usage?.taskCount)} ${t('dashboard.taskRuns')}`"
        icon="monitoring"
      />
      <StatCard
        :label="t('dashboard.balance')"
        :value="formatMicroEur(balance?.availableMicroEur)"
        :hint="`${t('dashboard.reserved')}: ${formatMicroEur(balance?.reservedMicroEur)}`"
        icon="account_balance_wallet"
      />
      <StatCard
        :label="t('dashboard.principal')"
        :value="principal?.displayName ?? '—'"
        :hint="principal?.email ?? session.sessionPublicId"
        icon="person"
      />
    </div>

    <article class="md-card">
      <PageHeader :title="t('dashboard.sessionTitle')" :subtitle="t('dashboard.sessionSubtitle')" />
      <dl class="stat-grid">
        <div>
          <dt class="stat-card__label">{{ t('dashboard.sessionId') }}</dt>
          <dd class="stat-card__value">{{ session.sessionPublicId }}</dd>
        </div>
        <div>
          <dt class="stat-card__label">{{ t('dashboard.workspaceId') }}</dt>
          <dd class="stat-card__value">{{ session.workspaceId }}</dd>
        </div>
        <div>
          <dt class="stat-card__label">{{ t('dashboard.authGeneration') }}</dt>
          <dd class="stat-card__value">{{ session.authorizationGeneration }}</dd>
        </div>
      </dl>
    </article>

    <article v-if="tasks?.items?.length" class="md-card">
      <PageHeader :title="t('dashboard.recentTasks')" />
      <div class="md-table-wrap">
        <table class="md-table">
          <thead>
            <tr>
              <th scope="col">{{ t('tasks.colId') }}</th>
              <th scope="col">{{ t('tasks.colType') }}</th>
              <th scope="col">{{ t('tasks.colLifecycle') }}</th>
              <th scope="col">{{ t('tasks.colExecution') }}</th>
              <th scope="col">{{ t('tasks.colCreated') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="task in tasks.items.slice(0, 5)" :key="task.id">
              <td>{{ task.id }}</td>
              <td>{{ task.taskType }}</td>
              <td><StatusChip :status="task.lifecycleStatus" /></td>
              <td><StatusChip :status="task.executionStatus" /></td>
              <td>{{ formatDateTime(task.createdAt) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </section>
</template>
