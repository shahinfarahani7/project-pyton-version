<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import MobilePageHeader from '../components/ui/MobilePageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';
import { formatDateTime, formatTaskType, statusTone } from '../utils/format';

const session = useSession();
const route = useRoute();
const router = useRouter();

const loading = ref(true);
const error = ref('');
const task = ref(null);

const taskId = computed(() => String(route.params.id ?? ''));

const displayStatus = computed(() => {
  const lifecycle = String(task.value?.lifecycleStatus ?? '').toLowerCase();
  if (['succeeded', 'completed'].includes(lifecycle)) return t('tasks.statusCompleted');
  if (['failed'].includes(lifecycle)) return t('tasks.statusFailed');
  if (['running', 'in_progress', 'queued'].includes(lifecycle)) return t('tasks.statusProcessing');
  return task.value?.lifecycleStatus ?? '—';
});

const statusClass = computed(() => {
  const tone = statusTone(task.value?.lifecycleStatus ?? task.value?.executionStatus);
  return `em-status-banner--${tone}`;
});

onMounted(async () => {
  if (!session.workspaceId || !session.hasPermission('customer.tasks:read')) {
    loading.value = false;
    return;
  }
  try {
    task.value = await portalApi.task(session.workspaceId, taskId.value);
  } catch (err) {
    error.value = err?.message ?? t('tasks.detailError');
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <section class="em-page em-page--detail">
    <MobilePageHeader
      class="em-page-header--mobile-only"
      :title="t('tasks.detailTitle')"
      show-back
      :back-to="{ name: 'tasks' }"
    />

    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
    <div v-if="loading" class="md-card"><div class="md-skeleton" style="height: 8rem" /></div>

    <template v-else-if="task">
      <div class="em-status-banner" :class="statusClass">{{ displayStatus }}</div>

      <div class="em-layout-detail">
        <div class="em-layout-detail__info">
          <article class="md-card em-info-card">
        <h2 class="em-section-title">{{ t('tasks.infoTitle') }}</h2>
        <dl class="em-kv-list">
          <div><dt>{{ t('tasks.colId') }}</dt><dd><code>{{ task.id }}</code></dd></div>
          <div><dt>{{ t('tasks.colCreated') }}</dt><dd>{{ formatDateTime(task.createdAt) }}</dd></div>
          <div><dt>{{ t('tasks.colType') }}</dt><dd>{{ formatTaskType(task) }}</dd></div>
          <div><dt>{{ t('tasks.colInput') }}</dt><dd>{{ task.inputLabel ?? '—' }}</dd></div>
          <div><dt>{{ t('tasks.colLifecycle') }}</dt><dd><StatusChip :status="task.lifecycleStatus" /></dd></div>
          <div><dt>{{ t('tasks.colExecution') }}</dt><dd><StatusChip :status="task.executionStatus" /></dd></div>
          <div><dt>{{ t('tasks.colVersion') }}</dt><dd>{{ task.version }}</dd></div>
        </dl>
          </article>

          <article class="md-card em-info-card">
        <h2 class="em-section-title">{{ t('tasks.processingTitle') }}</h2>
        <dl class="em-kv-list">
          <div><dt>{{ t('tasks.startedAt') }}</dt><dd>{{ formatDateTime(task.updatedAt ?? task.createdAt) }}</dd></div>
          <div><dt>{{ t('tasks.completedAt') }}</dt><dd>{{ formatDateTime(task.updatedAt) }}</dd></div>
          <div v-if="task.assignmentId"><dt>{{ t('tasks.assignmentId') }}</dt><dd><code>{{ task.assignmentId }}</code></dd></div>
        </dl>
          </article>
        </div>

        <article class="md-card em-result-card">
        <div class="em-result-card__header">
          <h2 class="em-section-title">{{ t('tasks.resultTitle') }}</h2>
          <StatusChip :status="task.executionStatus" />
        </div>

        <div v-if="task.resultArtifactUrl" class="em-result-preview">
          <img
            v-if="task.resultArtifactUrl.includes('result-file')"
            :src="task.resultArtifactUrl"
            :alt="t('tasks.resultImageAlt')"
            class="em-result-preview__image"
          />
          <a
            class="md-btn md-btn-filled"
            :href="task.resultArtifactUrl"
            :download="task.inputLabel ? `result-${task.inputLabel}` : `result-${task.id}`"
          >
            <span class="material-symbols-outlined" aria-hidden="true">download</span>
            {{ t('tasks.downloadResult') }}
          </a>
        </div>

        <div v-if="task.resultPreview" class="em-result-summary">
          <p class="em-result-summary__label">{{ t('tasks.resultPreview') }}</p>
          <p class="em-result-summary__value">{{ task.resultPreview }}</p>
        </div>

        <div class="em-raw-json">
          <p class="em-section-title">{{ t('tasks.rawResponse') }}</p>
          <pre class="em-code-block">{{ JSON.stringify(task, null, 2) }}</pre>
        </div>
      </article>
      </div>

      <button type="button" class="md-btn md-btn-outlined em-back-btn" @click="router.push({ name: 'tasks' })">
        {{ t('tasks.backToList') }}
      </button>
    </template>
  </section>
</template>
