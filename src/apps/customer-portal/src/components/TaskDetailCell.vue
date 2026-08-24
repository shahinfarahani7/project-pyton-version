<script setup>
import { computed } from 'vue';

import StatusChip from './ui/StatusChip.vue';
import { t } from '../i18n';
import { taskResultState } from '../utils/taskResult';

const props = defineProps({
  task: { type: Object, required: true },
});

const state = computed(() => taskResultState(props.task));

const hint = computed(() => {
  if (state.value.kind === 'text' || state.value.kind === 'file') {
    return t('tasks.viewDetailWithResult');
  }
  if (state.value.kind === 'pending') {
    return t('tasks.viewDetailPending');
  }
  if (state.value.kind === 'failed') {
    return t('tasks.viewDetailFailed');
  }
  return t('tasks.viewDetail');
});
</script>

<template>
  <div class="em-task-detail-cell">
    <StatusChip :status="task.lifecycleStatus" />
    <span class="em-task-detail-cell__hint">{{ hint }}</span>
    <span class="material-symbols-outlined em-task-detail-cell__icon" aria-hidden="true">chevron_right</span>
  </div>
</template>
