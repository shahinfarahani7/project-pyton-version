<script setup>
import { computed, ref, watch } from 'vue';

import { t } from '../i18n';

const props = defineProps({
  open: { type: Boolean, default: false },
  submitting: { type: Boolean, default: false },
  error: { type: String, default: '' },
});

const emit = defineEmits(['close', 'submit']);

const dialogEl = ref(null);
const taskType = ref('document.ocr');
const inputText = ref('');
const inputFile = ref(null);
const fileInputEl = ref(null);
const localError = ref('');

const taskTypes = [
  { value: 'document.ocr', labelKey: 'tasks.typeOcr' },
  { value: 'text.summarize', labelKey: 'tasks.typeSummarize' },
  { value: 'image.classify', labelKey: 'tasks.typeClassify' },
  { value: 'image.remove_background', labelKey: 'tasks.typeRemoveBackground' },
];

const acceptsByType = {
  'document.ocr': '.txt,.md,.pdf,image/*',
  'text.summarize': '.txt,.md,.csv,.json',
  'image.classify': 'image/*',
  'image.remove_background': 'image/*',
};

const acceptAttr = computed(() => acceptsByType[taskType.value] ?? '*/*');
const needsText = computed(() => taskType.value === 'text.summarize');
const needsImage = computed(() =>
  taskType.value === 'image.classify' || taskType.value === 'image.remove_background',
);
const allowsFile = computed(() => true);

watch(
  () => props.open,
  (open) => {
    if (open) {
      taskType.value = 'document.ocr';
      inputText.value = '';
      inputFile.value = null;
      localError.value = '';
      if (fileInputEl.value) {
        fileInputEl.value.value = '';
      }
      dialogEl.value?.showModal();
      return;
    }
    dialogEl.value?.close();
  },
);

function onCancel() {
  emit('close');
}

function onFileChange(event) {
  const [file] = event.target.files ?? [];
  inputFile.value = file ?? null;
  localError.value = '';
}

function clearFile() {
  inputFile.value = null;
  if (fileInputEl.value) {
    fileInputEl.value.value = '';
  }
}

function validatePayload() {
  const text = inputText.value.trim();
  const file = inputFile.value;
  if (needsText.value && !text && !file) {
    localError.value = t('tasks.inputTextRequired');
    return false;
  }
  if (!needsText.value && !text && !file) {
    localError.value = t('tasks.inputFileOrTextRequired');
    return false;
  }
  if (needsImage.value && !file) {
    localError.value = t('tasks.inputImageRequired');
    return false;
  }
  if (taskType.value === 'image.classify' && file && !file.type.startsWith('image/')) {
    localError.value = t('tasks.inputImageRequired');
    return false;
  }
  localError.value = '';
  return true;
}

function onSubmit() {
  if (!validatePayload()) {
    return;
  }
  emit('submit', {
    taskType: taskType.value,
    inputText: inputText.value.trim() || undefined,
    inputFile: inputFile.value ?? undefined,
  });
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

      <label class="md-field">
        <span>{{ t('tasks.inputTextLabel') }}</span>
        <textarea
          v-model="inputText"
          class="md-textarea"
          rows="5"
          :placeholder="t('tasks.inputTextPlaceholder')"
          :disabled="submitting"
        />
      </label>

      <div v-if="allowsFile" class="md-field">
        <span>{{ t('tasks.inputFileLabel') }}</span>
        <input
          ref="fileInputEl"
          type="file"
          class="md-input"
          :accept="acceptAttr"
          :disabled="submitting"
          @change="onFileChange"
        />
        <p v-if="inputFile" class="md-hint">
          {{ t('tasks.inputFileSelected', { name: inputFile.name }) }}
          <button type="button" class="md-btn md-btn-text md-btn-compact" @click="clearFile">
            {{ t('tasks.inputFileClear') }}
          </button>
        </p>
        <p class="md-hint">{{ t('tasks.inputFileHint') }}</p>
      </div>

      <p v-if="localError || error" class="md-alert md-alert--error" role="alert">
        {{ localError || error }}
      </p>

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
