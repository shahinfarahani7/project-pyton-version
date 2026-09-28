<script setup>
import { ref, watch } from 'vue';

import { resolveTaskTypeForIntake, taskTypeAccept } from '../config/taskTypeCatalog';
import { t } from '../i18n';

const props = defineProps({
  submitting: { type: Boolean, default: false },
  error: { type: String, default: '' },
  showCancel: { type: Boolean, default: false },
  resetKey: { type: Number, default: 0 },
});

const emit = defineEmits(['submit', 'cancel']);

const instructions = ref('');
const inputFile = ref(null);
const fileInputEl = ref(null);
const localError = ref('');
const dragOver = ref(false);

const acceptAttr = taskTypeAccept('text.direct');

function resetForm() {
  instructions.value = '';
  inputFile.value = null;
  localError.value = '';
  if (fileInputEl.value) {
    fileInputEl.value.value = '';
  }
}

watch(() => props.resetKey, resetForm);

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

function validatePayload() {
  const note = instructions.value.trim();
  const file = inputFile.value;
  const taskType = resolveTaskTypeForIntake({ file, instructions: note });

  if (!taskType) {
    localError.value = t('tasks.inputFileOrTextRequired');
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
  const note = instructions.value.trim();
  const file = inputFile.value;
  const taskType = resolveTaskTypeForIntake({ file, instructions: note });
  emit('submit', {
    taskType,
    instructions: note || undefined,
    inputFile: file ?? undefined,
  });
}
</script>

<template>
  <form class="task-submit-form" @submit.prevent="onSubmit">
    <label class="md-field">
      <span class="field-label">{{ t('tasks.instructionsLabel') }}</span>
      <textarea
        v-model="instructions"
        class="md-textarea"
        rows="4"
        :placeholder="t('tasks.instructionsPlaceholder')"
        :disabled="submitting"
      />
      <p class="md-hint">{{ t('tasks.instructionsHint') }}</p>
    </label>

    <div
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
        :accept="acceptAttr"
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
