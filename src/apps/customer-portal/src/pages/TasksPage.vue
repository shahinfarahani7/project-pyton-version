<script setup>
import { computed, ref } from 'vue';
import { RouterLink } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import { useTaskEventStream } from '../composables/useTaskEventStream';
import TaskCreateDialog from '../components/TaskCreateDialog.vue';
import TaskDetailCell from '../components/TaskDetailCell.vue';
import EmptyState from '../components/ui/EmptyState.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { mapTaskInputError } from '../config/taskTypeCatalog';
import { t } from '../i18n';
import { formatDateTime, formatTaskType } from '../utils/format';
import { sortTasksNewestFirst } from '../utils/taskSort';
import { trackEvent } from '../telemetry';

const session = useSession();
const createOpen = ref(false);
const createFormKey = ref(0);
const creating = ref(false);
const createError = ref('');
const searchQuery = ref('');
const typeFilter = ref('all');
const statusFilter = ref('all');

const { data: tasks, error, loading, refresh } = useAsyncResource(
  () => {
    trackEvent('portal.page.tasks');
    return portalApi.tasks(session.workspaceId);
  },
  { enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.tasks:read')) },
);

function applyTaskEvent(event) {
  if (!event?.task || !tasks.value?.items) {
    void refresh({ silent: true });
    return;
  }
  const items = [...tasks.value.items];
  const index = items.findIndex((item) => item.id === event.taskId);
  if (index >= 0) {
    items[index] = event.task;
  } else {
    items.unshift(event.task);
  }
  tasks.value = { ...tasks.value, items: sortTasksNewestFirst(items) };
}

useTaskEventStream(() => session.workspaceId, {
  enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.tasks:read')),
  onTaskEvent: applyTaskEvent,
});

const typeOptions = computed(() => {
  const types = new Set((tasks.value?.items ?? []).map((task) => task.taskType));
  return ['all', ...types];
});

const filteredTasks = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  return sortTasksNewestFirst(
    (tasks.value?.items ?? []).filter((task) => {
    const matchesType = typeFilter.value === 'all' || task.taskType === typeFilter.value;
    const lifecycle = String(task.lifecycleStatus).toLowerCase();
    const matchesStatus =
      statusFilter.value === 'all' ||
      lifecycle === statusFilter.value ||
      String(task.executionStatus).toLowerCase() === statusFilter.value;
    const label = formatTaskType(task).toLowerCase();
    const matchesQuery =
      !query ||
      task.id.toLowerCase().includes(query) ||
      task.taskType.toLowerCase().includes(query) ||
      label.includes(query);
    return matchesType && matchesStatus && matchesQuery;
    }),
  );
});

function openCreateDialog() {
  createError.value = '';
  createFormKey.value += 1;
  createOpen.value = true;
}

function closeCreateDialog() {
  createOpen.value = false;
}

async function submitCreateTask(payload) {
  if (!session.workspaceId || !session.hasPermission('customer.tasks:write')) {
    return;
  }
  creating.value = true;
  createError.value = '';
  trackEvent('portal.tasks.create', {
    taskType: payload.taskType,
    hasFile: Boolean(payload.inputFile),
    hasInstructions: Boolean(payload.instructions),
  });
  try {
    await portalApi.createTask(session.workspaceId, payload);
    createError.value = '';
    closeCreateDialog();
    try {
      await refresh({ silent: true });
    } catch {
      // Task was created; SSE or a later refresh will update the list.
    }
  } catch (err) {
    const mapped = mapTaskInputError(err);
    createError.value = mapped ? t(mapped) : err?.message ?? t('tasks.createError');
  } finally {
    creating.value = false;
  }
}
</script>

<template>
  <section class="em-page">
    <div class="em-page-toolbar">
      <div class="em-filter-row">
        <select v-model="typeFilter" class="md-select em-filter-select">
          <option value="all">{{ t('tasks.filterAllTypes') }}</option>
          <option v-for="type in typeOptions.filter((v) => v !== 'all')" :key="type" :value="type">
            {{ type }}
          </option>
        </select>
        <select v-model="statusFilter" class="md-select em-filter-select">
          <option value="all">{{ t('tasks.filterAllStatus') }}</option>
          <option value="completed">{{ t('tasks.statusCompleted') }}</option>
          <option value="succeeded">{{ t('tasks.statusCompleted') }}</option>
          <option value="running">{{ t('tasks.statusProcessing') }}</option>
          <option value="queued">{{ t('tasks.statusProcessing') }}</option>
          <option value="failed">{{ t('tasks.statusFailed') }}</option>
        </select>
      </div>
      <label class="em-search-field">
        <span class="material-symbols-outlined" aria-hidden="true">search</span>
        <input
          v-model="searchQuery"
          type="search"
          class="md-input"
          :placeholder="t('tasks.searchPlaceholder')"
        />
      </label>
      <button
        v-if="session.hasPermission('customer.tasks:write')"
        type="button"
        class="md-btn md-btn-filled md-btn-block em-create-task-btn"
        data-testid="create-task"
        @click="openCreateDialog"
      >
        <span class="material-symbols-outlined" aria-hidden="true">add</span>
        {{ t('tasks.create') }}
      </button>
    </div>

    <TaskCreateDialog
      :open="createOpen"
      :form-key="createFormKey"
      :submitting="creating"
      :error="createError"
      @close="closeCreateDialog"
      @submit="submitCreateTask"
    />

    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <p v-if="createError && !createOpen" class="md-alert md-alert--error" role="alert">{{ createError }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 6rem" /></div>
    <EmptyState
      v-else-if="!filteredTasks.length"
      :title="t('tasks.emptyTitle')"
      :description="t('tasks.emptyBody')"
      icon="assignment"
    />
    <ul v-else class="em-task-list em-task-list--full">
      <li class="em-task-list__header" aria-hidden="true">
        <span>{{ t('tasks.colId') }}</span>
        <span>{{ t('tasks.colDetail') }}</span>
        <span>{{ t('tasks.colCreated') }}</span>
      </li>
      <li v-for="task in filteredTasks" :key="task.id">
        <RouterLink :to="{ name: 'task-detail', params: { id: task.id } }" class="em-task-row">
          <div class="em-task-row__primary">
            <code class="em-task-row__id">{{ task.id.slice(0, 8) }}</code>
            <p class="em-task-row__type">{{ formatTaskType(task) }}</p>
          </div>
          <TaskDetailCell :task="task" />
          <div class="em-task-row__meta">
            <StatusChip :status="task.lifecycleStatus" />
            <span>{{ formatDateTime(task.createdAt) }}</span>
          </div>
        </RouterLink>
      </li>
    </ul>
  </section>
</template>
