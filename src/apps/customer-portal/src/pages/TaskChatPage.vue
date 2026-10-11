<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { RouterLink } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import BrandLockup from '../components/BrandLockup.vue';
import StrokeIcon from '../components/ui/StrokeIcon.vue';
import TaskSubmitForm from '../components/TaskSubmitForm.vue';
import { useTaskEventStream } from '../composables/useTaskEventStream';
import { mapTaskInputError } from '../config/taskTypeCatalog';
import { t } from '../i18n';
import { taskListTitle, taskStatusGroup } from '../utils/format';
import { taskAwaitingResult, taskResultDownloadName, taskResultState } from '../utils/taskResult';
import { trackEvent } from '../telemetry';

const session = useSession();
const turns = ref([]);
const selectedId = ref('');
const creating = ref(false);
const loading = ref(true);
const listError = ref('');
const cancellingTaskId = ref('');
const formKey = ref(0);
const copied = ref(false);
const historyQuery = ref('');
const threadEl = ref(null);
let pollTimer = 0;

function fileLabel(task, prompt) {
  const label = String(task?.inputLabel ?? '').trim();
  if (!label || label === prompt || label === 'Pasted text' || label === 'Customer upload') {
    return '';
  }
  return label;
}

function turnFromTask(task) {
  const prompt = taskListTitle(task);
  return {
    localId: task.id,
    prompt,
    fileName: fileLabel(task, prompt),
    task,
    error: '',
    fromHistory: true,
  };
}

function chronological(items) {
  return [...items].sort(
    (left, right) => (Date.parse(left?.createdAt ?? '') || 0) - (Date.parse(right?.createdAt ?? '') || 0),
  );
}

function isWaiting(turn) {
  const lifecycle = String(turn.task?.lifecycleStatus ?? '').toLowerCase();
  if (turn.fromHistory && ['succeeded', 'completed', 'failed', 'cancelled', 'canceled', 'expired'].includes(lifecycle)) {
    return false;
  }
  if (turn.error || !turn.task) {
    return !turn.error && !turn.task;
  }
  if (['failed', 'cancelled', 'canceled', 'expired'].includes(lifecycle)) {
    return false;
  }
  return taskAwaitingResult(turn.task);
}

function resultFileUrl(turn) {
  return turn.task?.resultArtifactUrl || '';
}

function isImageResult(url) {
  return /result-file|\.(png|jpe?g|gif|webp)(\?|$)/i.test(url);
}

function copyableAnswer(turn) {
  const text = answerText(turn);
  const fileUrl = resultFileUrl(turn);
  if (!text || text === fileUrl) {
    return '';
  }
  return text;
}

function answerText(turn) {
  const task = turn.task;
  if (!task) {
    return '';
  }
  const lifecycle = String(task.lifecycleStatus ?? '').toLowerCase();
  if (lifecycle === 'failed') {
    return task.failureReason || task.failureReasonCode || t('tasks.chatFailed');
  }
  if (['cancelled', 'canceled'].includes(lifecycle)) {
    return t('tasks.statusCancel');
  }
  const state = taskResultState(task);
  if (state.kind === 'text') return state.text;
  if (state.kind === 'file') return state.url;
  return '';
}

function canCancel(turn) {
  const lifecycle = String(turn.task?.lifecycleStatus ?? '').toLowerCase();
  return Boolean(turn.task?.id)
    && session.hasPermission('customer.tasks:write')
    && !['succeeded', 'completed', 'failed', 'cancelled', 'expired'].includes(lifecycle);
}

const hasPending = computed(() => turns.value.some((turn) => turn.task?.id && isWaiting(turn)));
const sidebarTurns = computed(() => [...turns.value].reverse());
const visibleHistory = computed(() => {
  const query = historyQuery.value.trim().toLowerCase();
  if (!query) return sidebarTurns.value;
  return sidebarTurns.value.filter((turn) => turnTitle(turn).toLowerCase().includes(query));
});
const selectedTurn = computed(() => turns.value.find((turn) => turn.localId === selectedId.value) ?? null);

async function selectTurn(turn) {
  selectedId.value = turn.localId;
  copied.value = false;
  if (!turn.fromHistory || !turn.task?.id || !session.workspaceId) {
    return;
  }
  if (answerText(turn) || resultFileUrl(turn) || turn.error) {
    return;
  }
  try {
    const task = await portalApi.task(session.workspaceId, turn.task.id);
    replaceTurn(turn.localId, { ...turn, task, fromHistory: true, error: '' });
  } catch {
    // Keep the stored list snapshot. Selecting history never creates a task.
  }
}

function newChat() {
  selectedId.value = '';
  copied.value = false;
}

function historyDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date);
}

function historyTone(turn) {
  const group = taskStatusGroup(turn.task?.lifecycleStatus);
  if (group === 'done') return '';
  if (group === 'running') return 'blue';
  if (group === 'queued') return 'warn';
  if (group === 'failed') return 'bad';
  return 'neutral';
}

function historyLabel(turn) {
  const group = taskStatusGroup(turn.task?.lifecycleStatus);
  if (group === 'done') return t('dashboard.statusSucceeded');
  if (group === 'running') return t('dashboard.statusRunning');
  if (group === 'queued') return t('dashboard.statusQueued');
  if (group === 'failed') return t('dashboard.statusFailed');
  if (group === 'cancel') return t('dashboard.statusCancelled');
  return turnStatus(turn);
}

async function copyAnswer(text) {
  if (!text) {
    return;
  }
  await navigator.clipboard.writeText(text);
  copied.value = true;
  window.setTimeout(() => {
    copied.value = false;
  }, 1500);
}

const STATUS_LABELS = {
  done: 'tasks.statusDone',
  running: 'tasks.statusRunning',
  queued: 'tasks.statusQueued',
  cancel: 'tasks.statusCancel',
};

function turnStatus(turn) {
  const key = STATUS_LABELS[taskStatusGroup(turn.task?.lifecycleStatus)];
  return key ? t(key) : '';
}

function turnTitle(turn) {
  return turn.prompt || turn.fileName || t('tasks.createTitle');
}

function stopPoll() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = 0;
  }
}

function replaceTurn(localId, next) {
  const index = turns.value.findIndex((item) => item.localId === localId);
  if (index >= 0) {
    turns.value[index] = next;
  }
}

async function refreshPending() {
  const pending = turns.value.filter((turn) => turn.task?.id && isWaiting(turn));
  if (!pending.length || !session.workspaceId) {
    stopPoll();
    return;
  }
  await Promise.all(
    pending.map(async (turn) => {
      try {
        const next = await portalApi.task(session.workspaceId, turn.task.id);
        replaceTurn(turn.localId, { ...turn, task: next });
      } catch {
        // Keep the previous task until the next refresh.
      }
    }),
  );
  if (!turns.value.some((turn) => turn.task?.id && isWaiting(turn))) {
    stopPoll();
  }
}

function ensurePoll() {
  if (pollTimer || !hasPending.value) {
    return;
  }
  pollTimer = setInterval(() => {
    void refreshPending();
  }, 2000);
}

function applyLoadedTasks(items) {
  const ordered = chronological(items).map(turnFromTask);
  const known = new Set(ordered.map((turn) => turn.task.id));
  const pendingLocal = turns.value.filter((turn) => !turn.task?.id);
  const extras = turns.value.filter((turn) => turn.task?.id && !known.has(turn.task.id));
  const localById = new Map(
    turns.value.filter((turn) => turn.task?.id).map((turn) => [turn.task.id, turn]),
  );
  turns.value = [
    ...ordered.map((turn) => {
      const existing = localById.get(turn.task.id);
      if (!existing) return turn;
      return {
        ...turn,
        localId: existing.localId,
        prompt: existing.prompt || turn.prompt,
        fileName: existing.fileName || turn.fileName,
        fromHistory: existing.fromHistory === true,
      };
    }),
    ...extras,
    ...pendingLocal,
  ];
  if (hasPending.value) {
    ensurePoll();
  }
}

async function loadHistory() {
  if (!session.workspaceId || !session.hasPermission('customer.tasks:read')) {
    loading.value = false;
    return;
  }
  loading.value = turns.value.length === 0;
  try {
    trackEvent('portal.page.tasks');
    const body = await portalApi.tasks(session.workspaceId);
    applyLoadedTasks(body?.items ?? []);
    listError.value = '';
  } catch (err) {
    const mapped = mapTaskInputError(err);
    listError.value = mapped ? t(mapped) : err?.message ?? t('tasks.detailError');
  } finally {
    loading.value = false;
  }
}

useTaskEventStream(() => session.workspaceId, {
  enabled: () => Boolean(session.workspaceId && session.hasPermission('customer.tasks:read')),
  onTaskEvent(event) {
    const task = event?.task;
    const taskId = event?.taskId ?? task?.id;
    if (!task || !taskId) {
      void loadHistory();
      return;
    }
    const index = turns.value.findIndex((turn) => turn.task?.id === taskId || turn.localId === taskId);
    if (index >= 0) {
      const current = turns.value[index];
      turns.value[index] = {
        ...current,
        task,
        prompt: current.prompt || taskListTitle(task),
      };
      return;
    }
    turns.value = [...turns.value, turnFromTask(task)];
  },
});

async function scrollAnswerToStart() {
  await nextTick();
  const thread = threadEl.value;
  if (!thread) {
    return;
  }
  thread.scrollTop = 0;
  thread.querySelector('.em-chat__row--user')?.scrollIntoView?.({ block: 'start' });
}

watch(selectedId, () => {
  void scrollAnswerToStart();
});

async function submit(payload) {
  if (!session.workspaceId || !session.hasPermission('customer.tasks:write') || creating.value) {
    return;
  }
  creating.value = true;
  const localId = `${Date.now()}-${turns.value.length}`;
  turns.value = [
    ...turns.value,
    {
      localId,
      prompt: payload.instructions || '',
      fileName: payload.inputFile?.name || '',
      task: null,
      error: '',
    },
  ];
  selectedId.value = localId;
  trackEvent('portal.tasks.create', {
    taskType: payload.taskType,
    hasFile: Boolean(payload.inputFile),
    hasInstructions: Boolean(payload.instructions),
  });
  try {
    const task = await portalApi.createTask(session.workspaceId, payload);
    replaceTurn(localId, {
      localId,
      prompt: payload.instructions || taskListTitle(task),
      fileName: payload.inputFile?.name || '',
      task,
      error: '',
    });
    formKey.value += 1;
    if (hasPending.value) {
      void refreshPending();
      ensurePoll();
    }
  } catch (err) {
    const mapped = mapTaskInputError(err);
    replaceTurn(localId, {
      localId,
      prompt: payload.instructions || '',
      fileName: payload.inputFile?.name || '',
      task: null,
      error: mapped ? t(mapped) : err?.message ?? t('tasks.createError'),
    });
  } finally {
    creating.value = false;
  }
}

async function cancelTurn(turn) {
  if (!canCancel(turn) || !session.workspaceId) {
    return;
  }
  if (!window.confirm(t('tasks.cancelConfirm'))) {
    return;
  }
  cancellingTaskId.value = turn.task.id;
  try {
    const cancelled = await portalApi.cancelTask(session.workspaceId, turn.task.id);
    replaceTurn(turn.localId, { ...turn, task: cancelled, error: '' });
  } catch (err) {
    replaceTurn(turn.localId, {
      ...turn,
      error: err?.message ?? t('tasks.cancelError'),
    });
  } finally {
    cancellingTaskId.value = '';
  }
}

onMounted(() => {
  void loadHistory();
});

onUnmounted(stopPoll);
</script>

<template>
  <section class="em-chat-page">
    <aside class="em-chat-history" :aria-label="t('nav.tasks')">
      <div class="em-chat-history__head">
        <h2>{{ t('tasks.yourTasks') }}</h2>
        <button type="button" class="em-chat-history__new" :aria-label="t('tasks.newTask')" @click="newChat">
          <StrokeIcon name="plus" />
        </button>
      </div>
      <label class="em-chat-history__search">
        <StrokeIcon name="search" />
        <input v-model="historyQuery" type="search" :aria-label="t('tasks.searchRequests')" :placeholder="t('tasks.searchRequests')" />
      </label>
      <p v-if="listError" class="md-alert md-alert--error" role="alert">{{ listError }}</p>
      <div v-if="loading" class="md-skeleton" style="height: 6rem" />
      <div v-else class="em-chat-list">
        <p v-if="!visibleHistory.length" class="em-chat-history__empty">{{ t('tasks.noMatches') }}</p>
        <ul v-else>
          <li v-for="turn in visibleHistory" :key="turn.localId">
            <button
              type="button"
              class="em-chat-list__item"
              :class="{ 'em-chat-list__item--active': turn.localId === selectedId }"
              @click="selectTurn(turn)"
            >
              <span class="em-chat-list__title">{{ turnTitle(turn) }}</span>
              <span v-if="turn.task" class="em-chat-list__meta">
                <span class="fn-badge" :class="historyTone(turn) ? `fn-badge--${historyTone(turn)}` : ''">
                  {{ historyLabel(turn) }}
                </span>
                <time>{{ historyDate(turn.task.createdAt) }}</time>
              </span>
            </button>
          </li>
        </ul>
      </div>
      <p class="em-chat-history__foot">
        <StrokeIcon name="lock" />
        {{ t('tasks.historyFoot') }}
      </p>
    </aside>

    <div class="em-chat-main">
      <header class="em-chat-top">
        <span class="em-chat-top__product">
          <BrandLockup class="fn-logo--chat" />
        </span>
        <div class="em-chat-top__actions">
          <span
            v-if="selectedTurn?.task"
            class="fn-badge"
            :class="historyTone(selectedTurn) ? `fn-badge--${historyTone(selectedTurn)}` : ''"
          >
            {{ historyLabel(selectedTurn) }}
          </span>
          <span v-else class="fn-badge fn-badge--neutral">{{ t('tasks.newRequest') }}</span>
          <RouterLink
            v-if="selectedTurn?.task?.id"
            class="md-btn"
            :to="{ name: 'task-detail', params: { id: selectedTurn.task.id } }"
          >
            <StrokeIcon name="file" />
            {{ t('tasks.taskDetails') }}
          </RouterLink>
        </div>
      </header>
      <div ref="threadEl" class="em-chat-page__thread">
        <div v-if="!selectedTurn" class="em-chat-page__empty">
          <BrandLockup class="em-chat-welcome__mark" :wordmark="false" />
          <p class="fn-eyebrow">{{ t('tasks.welcomeEyebrow') }}</p>
          <h1>{{ t('tasks.welcomeTitle') }}</h1>
          <p>{{ t('tasks.welcomeBody') }}</p>
          <div class="em-chat-welcome__hints">
            <span><StrokeIcon name="file" />{{ t('tasks.hintDocuments') }}</span>
            <span><StrokeIcon name="tasks" />{{ t('tasks.hintWriting') }}</span>
            <span><StrokeIcon name="chart" />{{ t('tasks.hintAnalysis') }}</span>
          </div>
        </div>

        <template v-else>
          <div class="em-chat__row em-chat__row--user">
            <div class="em-chat__bubble em-chat__bubble--user">
              <span class="em-chat__caption">{{ t('tasks.yourRequest') }}</span>
              {{ turnTitle(selectedTurn) }}
              <span v-if="selectedTurn.fileName" class="em-chat__file">{{ selectedTurn.fileName }}</span>
            </div>
          </div>
          <div class="em-chat__row">
            <div class="em-chat__answer">
              <div class="em-chat__assistant-label">
                <BrandLockup class="fn-logo--assistant" />
                <span v-if="selectedTurn.task?.taskType" class="em-chat__assistant-type">{{ selectedTurn.task.taskType }}</span>
              </div>
              <div
                v-if="copyableAnswer(selectedTurn) || selectedTurn.error"
                class="em-chat__bubble em-chat__bubble--assistant em-chat__bubble--copyable"
                :class="{ 'em-chat__bubble--failed': selectedTurn.error || String(selectedTurn.task?.lifecycleStatus).toLowerCase() === 'failed' }"
              >
                <button
                  v-if="copyableAnswer(selectedTurn)"
                  type="button"
                  class="md-btn md-btn-text md-btn-compact em-chat__copy em-chat__copy--top"
                  :aria-label="copied ? t('tasks.copiedFullText') : t('tasks.copyFullText')"
                  @click="copyAnswer(copyableAnswer(selectedTurn))"
                >
                  <span class="material-symbols-outlined" aria-hidden="true">content_copy</span>
                </button>
                <p class="em-chat__answer-text">{{ selectedTurn.error || copyableAnswer(selectedTurn) }}</p>
                <button
                  v-if="copyableAnswer(selectedTurn)"
                  type="button"
                  class="md-btn md-btn-text md-btn-compact em-chat__copy"
                  @click="copyAnswer(copyableAnswer(selectedTurn))"
                >
                  <span class="material-symbols-outlined" aria-hidden="true">content_copy</span>
                  {{ copied ? t('tasks.copiedFullText') : t('tasks.copyFullText') }}
                </button>
              </div>
              <div v-if="resultFileUrl(selectedTurn)" class="em-chat__file-result">
                <img
                  v-if="isImageResult(resultFileUrl(selectedTurn))"
                  :src="resultFileUrl(selectedTurn)"
                  :alt="t('tasks.resultImageAlt')"
                  class="em-chat__result-image"
                />
                <p v-else class="em-chat__bubble em-chat__bubble--assistant">{{ t('tasks.resultFileReady') }}</p>
                <a
                  class="md-btn md-btn-filled em-chat__download"
                  :href="resultFileUrl(selectedTurn)"
                  :download="taskResultDownloadName(selectedTurn.task)"
                >
                  <span class="material-symbols-outlined" aria-hidden="true">download</span>
                  {{ t('tasks.downloadResult') }}
                </a>
              </div>
              <p
                v-if="isWaiting(selectedTurn) && !copyableAnswer(selectedTurn) && !resultFileUrl(selectedTurn) && !selectedTurn.error"
                class="em-chat__bubble em-chat__bubble--assistant em-chat__typing"
                aria-live="polite"
              >
                <span />
                <span />
                <span />
                <span class="visually-hidden">{{ t('tasks.submitting') }}</span>
              </p>
              <button
                v-if="canCancel(selectedTurn)"
                type="button"
                class="md-btn md-btn-text em-task-cancel-btn"
                :disabled="cancellingTaskId === selectedTurn.task.id"
                @click="cancelTurn(selectedTurn)"
              >
                {{ cancellingTaskId === selectedTurn.task.id ? t('tasks.cancelling') : t('tasks.cancelTask') }}
              </button>
            </div>
          </div>
        </template>
      </div>

      <TaskSubmitForm
        v-if="session.hasPermission('customer.tasks:write')"
        composer-only
        :submitting="creating"
        :reset-key="formKey"
        @submit="submit"
      />
    </div>
  </section>
</template>
