<script setup>
import { ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import TaskCreateDialog from '../components/TaskCreateDialog.vue';
import EmptyState from '../components/ui/EmptyState.vue';
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

const session = useSession();
const createOpen = ref(false);
const creating = ref(false);
const createError = ref('');

const { data: tasks, error, loading, refresh } = useAsyncResource(
  () => {
    trackEvent('portal.page.tasks');
    return portalApi.tasks(session.workspaceId);
  },
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.tasks:read')) },
);

function openCreateDialog() {
  createError.value = '';
  createOpen.value = true;
}

function closeCreateDialog() {
  createOpen.value = false;
  createError.value = '';
}

async function submitCreateTask(taskType) {
  if (!session.workspaceId || !session.hasPermission('customer.tasks:write')) {
    return;
  }
  creating.value = true;
  createError.value = '';
  trackEvent('portal.tasks.create', { taskType });
  try {
    await portalApi.createTask(session.workspaceId, { taskType });
    await refresh();
    closeCreateDialog();
  } catch (err) {
    createError.value = err?.message ?? t('tasks.createError');
  } finally {
    creating.value = false;
  }
}
</script>

<template>
  <section>
    <PageHeader :title="t('nav.tasks')" :subtitle="t('tasks.subtitle')">
      <template #actions>
        <button
          v-if="session.hasPermission('customer.tasks:write')"
          type="button"
          class="md-btn md-btn-filled"
          data-testid="create-task"
          @click="openCreateDialog"
        >
          <span class="material-symbols-outlined" aria-hidden="true">add</span>
          {{ t('tasks.create') }}
        </button>
      </template>
    </PageHeader>

    <TaskCreateDialog
      :open="createOpen"
      :submitting="creating"
      :error="createError"
      @close="closeCreateDialog"
      @submit="submitCreateTask"
    />

    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" /></div>
    <EmptyState
      v-else-if="!(tasks?.items?.length)"
      :title="t('tasks.emptyTitle')"
      :description="t('tasks.emptyBody')"
      icon="assignment"
    />
    <div v-else class="md-table-wrap">
      <table class="md-table">
        <caption class="visually-hidden">{{ t('nav.tasks') }}</caption>
        <thead>
          <tr>
            <th scope="col">{{ t('tasks.colId') }}</th>
            <th scope="col">{{ t('tasks.colType') }}</th>
            <th scope="col">{{ t('tasks.colLifecycle') }}</th>
            <th scope="col">{{ t('tasks.colExecution') }}</th>
            <th scope="col">{{ t('tasks.colVersion') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="task in tasks.items" :key="task.id">
            <td><code>{{ task.id }}</code></td>
            <td>{{ task.taskType }}</td>
            <td><StatusChip :status="task.lifecycleStatus" /></td>
            <td><StatusChip :status="task.executionStatus" /></td>
            <td>{{ task.version }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
