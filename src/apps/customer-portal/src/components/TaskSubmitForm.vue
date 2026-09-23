<script setup>
import { computed, ref, watch } from 'vue';

import TaskTypePicker from './TaskTypePicker.vue';
import {
  getTaskType,
  taskTypeAccept,
  taskTypeNeedsFlexJson,
  taskTypeNeedsImage,
  taskTypeNeedsText,
} from '../config/taskTypeCatalog';
import { PHASE1_TEXT_SUMMARIZE_REGRESSION_OPTIONS } from '../config/summarizeOptions';
import { t } from '../i18n';

const props = defineProps({
  submitting: { type: Boolean, default: false },
  error: { type: String, default: '' },
  showCancel: { type: Boolean, default: false },
  resetKey: { type: Number, default: 0 },
});

const emit = defineEmits(['submit', 'cancel']);

const taskType = ref('document.ocr');
const inputMode = ref('image');
const instructions = ref('');
const inputText = ref('');
const inputUrl = ref('');
const inputFile = ref(null);
const fileInputEl = ref(null);
const localError = ref('');
const dragOver = ref(false);
const usePhase1RegressionOptions = ref(false);

const acceptAttr = computed(() => taskTypeAccept(taskType.value));
const needsText = computed(() => taskTypeNeedsText(taskType.value));
const needsImage = computed(() => taskTypeNeedsImage(taskType.value));
const needsFlexJson = computed(() => taskTypeNeedsFlexJson(taskType.value));
const isTextSummarize = computed(() => taskType.value === 'text.summarize');

const inputModes = [
  { id: 'image', labelKey: 'tasks.inputModeImage', icon: 'image' },
  { id: 'text', labelKey: 'tasks.inputModeText', icon: 'text_fields' },
  { id: 'file', labelKey: 'tasks.inputModeFile', icon: 'attach_file' },
  { id: 'url', labelKey: 'tasks.inputModeUrl', icon: 'link' },
];

function resetForm() {
  taskType.value = 'document.ocr';
  inputMode.value = 'image';
  instructions.value = '';
  inputText.value = '';
  inputUrl.value = '';
  inputFile.value = null;
  localError.value = '';
  usePhase1RegressionOptions.value = false;
  if (fileInputEl.value) {
    fileInputEl.value.value = '';
  }
}

watch(() => props.resetKey, resetForm);

watch(taskType, (value) => {
  if (taskTypeNeedsText(value)) {
    inputMode.value = 'text';
  } else if (taskTypeNeedsImage(value)) {
    inputMode.value = 'image';
  }
});

function setInputMode(mode) {
  inputMode.value = mode;
  localError.value = '';
}

function onFileChange(event) {
  const [file] = event.target.files ?? [];
  inputFile.value = file ?? null;
  localError.value = '';
}

function onDrop(event) {
  event.preventDefault();
  dragOver.value = false;
  const [file] = event.dataTransfer?.files ?? [];
  if (file) {
    inputFile.value = file;
    localError.value = '';
  }
}

function browseFiles() {
  fileInputEl.value?.click();
}

function clearFile() {
  inputFile.value = null;
  if (fileInputEl.value) {
    fileInputEl.value.value = '';
  }
}

function contentText() {
  const parts = [inputText.value.trim(), inputUrl.value.trim()].filter(Boolean);
  return parts.length ? parts.join('\n') : '';
}

function validatePayload() {
  const text = contentText();
  const note = instructions.value.trim();
  const file = inputFile.value;
  const entry = getTaskType(taskType.value);
  const hasCustomInput = Boolean(text || note || file);

  if (!hasCustomInput) {
    localError.value = '';
    return true;
  }

  if (needsText.value && !text && !file && !note) {
    localError.value = t('tasks.inputTextRequired');
    return false;
  }
  if (needsImage.value && !file) {
    localError.value = t('tasks.inputImageRequired');
    return false;
  }
  if (needsFlexJson.value && text) {
    try {
      const parsed = JSON.parse(text);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        localError.value = t('tasks.flexJsonRequired');
        return false;
      }
    } catch {
      localError.value = t('tasks.flexJsonRequired');
      return false;
    }
  }
  if (entry?.inputMode === 'image' && file && !file.type.startsWith('image/')) {
    localError.value = t('tasks.inputImageRequired');
    return false;
  }
  if (file && file.size > 2 * 1024 * 1024) {
    localError.value = t('tasks.inputFileTooLarge');
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
    instructions: instructions.value.trim() || undefined,
    inputText: contentText() || undefined,
    inputFile: inputFile.value ?? undefined,
    ...(isTextSummarize.value && usePhase1RegressionOptions.value
      ? { summarizeOptions: PHASE1_TEXT_SUMMARIZE_REGRESSION_OPTIONS }
      : {}),
  });
}
</script>

<template>
  <form class="task-submit-form" @submit.prevent="onSubmit">
    <label class="md-field">
      <span class="field-label">{{ t('tasks.selectType') }}</span>
      <TaskTypePicker v-model="taskType" :disabled="submitting" />
    </label>

    <label class="md-field">
      <span class="field-label">{{ t('tasks.instructionsLabel') }}</span>
      <textarea
        v-model="instructions"
        class="md-textarea"
        rows="3"
        :placeholder="t('tasks.instructionsPlaceholder')"
        :disabled="submitting"
      />
      <p class="md-hint">{{ t('tasks.instructionsHint') }}</p>
    </label>

    <label v-if="isTextSummarize" class="md-field md-field--checkbox">
      <input
        v-model="usePhase1RegressionOptions"
        type="checkbox"
        :disabled="submitting"
      />
      <span>{{ t('tasks.phase1RegressionOptions') }}</span>
    </label>

    <div class="input-mode-tabs" role="tablist" :aria-label="t('tasks.inputModeLabel')">
      <button
        v-for="mode in inputModes"
        :key="mode.id"
        type="button"
        role="tab"
        class="input-mode-tab"
        :class="{ 'input-mode-tab--active': inputMode === mode.id }"
        :aria-selected="inputMode === mode.id"
        @click="setInputMode(mode.id)"
      >
        <span class="material-symbols-outlined" aria-hidden="true">{{ mode.icon }}</span>
        {{ t(mode.labelKey) }}
      </button>
    </div>

    <div
      v-if="inputMode === 'image' || inputMode === 'file'"
      class="upload-zone"
      :class="{ 'upload-zone--active': dragOver }"
      @dragover.prevent="dragOver = true"
      @dragleave.prevent="dragOver = false"
      @drop="onDrop"
    >
      <span class="material-symbols-outlined upload-zone__icon" aria-hidden="true">cloud_upload</span>
      <p>{{ t('tasks.uploadHint') }}</p>
      <button type="button" class="md-btn md-btn-filled" @click="browseFiles">
        {{ t('tasks.browseFiles') }}
      </button>
      <input
        ref="fileInputEl"
        type="file"
        class="visually-hidden"
        :accept="inputMode === 'image' ? 'image/*' : acceptAttr"
        :disabled="submitting"
        @change="onFileChange"
      />
      <p v-if="inputFile" class="upload-zone__file">
        {{ t('tasks.inputFileSelected', { name: inputFile.name }) }}
        <button type="button" class="md-btn md-btn-text md-btn-compact" @click="clearFile">
          {{ t('tasks.inputFileClear') }}
        </button>
      </p>
    </div>

    <label v-if="inputMode === 'text'" class="md-field">
      <span class="field-label">{{ t('tasks.inputContentLabel') }}</span>
      <textarea
        v-model="inputText"
        class="md-textarea"
        rows="6"
        :placeholder="t('tasks.inputTextPlaceholder')"
        :disabled="submitting"
      />
    </label>

    <label v-if="inputMode === 'url'" class="md-field">
      <span class="field-label">{{ t('tasks.inputUrlLabel') }}</span>
      <input
        v-model="inputUrl"
        type="url"
        class="md-input"
        :placeholder="t('tasks.inputUrlPlaceholder')"
        :disabled="submitting"
      />
      <p class="md-hint">{{ t('tasks.inputUrlHint') }}</p>
    </label>

    <p v-if="localError || error" class="md-alert md-alert--error" role="alert">
      {{ localError || error }}
    </p>

    <div class="task-submit-form__actions">
      <button
        v-if="showCancel"
        type="button"
        class="md-btn md-btn-outlined"
        :disabled="submitting"
        @click="emit('cancel')"
      >
        {{ t('tasks.cancel') }}
      </button>
      <button type="submit" class="md-btn md-btn-filled md-btn-block" :disabled="submitting">
        <span v-if="submitting" class="md-spinner md-spinner--inline" aria-hidden="true" />
        <span v-else class="material-symbols-outlined" aria-hidden="true">send</span>
        {{ submitting ? t('tasks.submitting') : t('tasks.submitTask') }}
      </button>
    </div>
  </form>
</template>
