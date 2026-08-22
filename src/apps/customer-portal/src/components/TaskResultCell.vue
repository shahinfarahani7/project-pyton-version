<script setup>
import { computed } from 'vue';

import { t } from '../i18n';
import { taskResultDownloadName, taskResultState, truncateText } from '../utils/taskResult';

const props = defineProps({
  task: { type: Object, required: true },
});

const state = computed(() => taskResultState(props.task));
const previewText = computed(() => truncateText(state.value.text, 96));
const downloadName = computed(() => taskResultDownloadName(props.task));
</script>

<template>
  <div class="em-task-result" @click.stop>
    <template v-if="state.kind === 'text'">
      <p class="em-task-result__text" :title="state.text">{{ previewText }}</p>
      <a
        v-if="task.resultArtifactUrl"
        class="md-btn md-btn-text md-btn-compact em-task-result__download"
        :href="task.resultArtifactUrl"
        :download="downloadName"
      >
        <span class="material-symbols-outlined" aria-hidden="true">download</span>
        {{ t('tasks.downloadResult') }}
      </a>
    </template>

    <template v-else-if="state.kind === 'file'">
      <p class="em-task-result__text em-task-result__text--muted">{{ t('tasks.resultFileReady') }}</p>
      <a
        class="md-btn md-btn-text md-btn-compact em-task-result__download"
        :href="state.url"
        :download="downloadName"
      >
        <span class="material-symbols-outlined" aria-hidden="true">download</span>
        {{ t('tasks.downloadResult') }}
      </a>
    </template>

    <p v-else-if="state.kind === 'pending'" class="em-task-result__text em-task-result__text--muted">
      {{ t('tasks.resultPending') }}
    </p>

    <p v-else-if="state.kind === 'failed'" class="em-task-result__text em-task-result__text--failed">
      {{ t('tasks.resultFailed') }}
    </p>

    <p v-else class="em-task-result__text em-task-result__text--muted">{{ t('tasks.resultNone') }}</p>
  </div>
</template>
