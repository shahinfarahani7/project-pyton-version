<script setup>
import { ref, watch } from 'vue';

import { t } from '../i18n';

const props = defineProps({
  open: { type: Boolean, default: false },
  submitting: { type: Boolean, default: false },
  error: { type: String, default: '' },
});

const emit = defineEmits(['close', 'submit']);

const dialogEl = ref(null);
const taskType = ref('document.ocr');

const taskTypes = [
  { value: 'document.ocr', labelKey: 'tasks.typeOcr' },
  { value: 'text.summarize', labelKey: 'tasks.typeSummarize' },
  { value: 'image.classify', labelKey: 'tasks.typeClassify' },
];

watch(
  () => props.open,
  (open) => {
    if (open) {
      taskType.value = 'document.ocr';
      dialogEl.value?.showModal();
      return;
    }
    dialogEl.value?.close();
  },
);

function onCancel() {
  emit('close');
}

function onSubmit() {
  emit('submit', taskType.value);
}
</script>

<template>
  <dialog ref="dialogEl" class="md-dialog" @close="onCancel">
    <form method="dialog" class="md-dialog__panel md-card" @submit.prevent="onSubmit">
      <header class="md-dialog__header">
        <h2 class="page-title">{{ t('tasks.createTitle') }}</h2>
        <p class="page-subtitle">{{ t('tasks.createSubtitle') }}</p>
      </header>
      <label class="md-field">
        <span>{{ t('tasks.colType') }}</span>
        <select v-model="taskType" class="md-select" required :disabled="submitting">
          <option v-for="option in taskTypes" :key="option.value" :value="option.value">
            {{ t(option.labelKey) }}
          </option>
        </select>
      </label>
      <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
      <footer class="md-dialog__actions">
        <button type="button" class="md-btn md-btn-text" :disabled="submitting" @click="onCancel">
          {{ t('tasks.cancel') }}
        </button>
        <button type="submit" class="md-btn md-btn-filled" :disabled="submitting">
          <span class="material-symbols-outlined" aria-hidden="true">add_task</span>
          {{ t('tasks.create') }}
        </button>
      </footer>
    </form>
  </dialog>
</template>
