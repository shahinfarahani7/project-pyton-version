<script setup>
import { nextTick, ref, watch } from 'vue';

import { resolveTaskTypeForIntake, taskTypeAccept } from '../config/taskTypeCatalog';
import { t } from '../i18n';

const props = defineProps({
  submitting: { type: Boolean, default: false },
  error: { type: String, default: '' },
  showCancel: { type: Boolean, default: false },
  resetKey: { type: Number, default: 0 },
  composerOnly: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'cancel']);

const instructions = ref('');
const composerEl = ref(null);
const inputFile = ref(null);
const fileInputEl = ref(null);
const localError = ref('');
const dragOver = ref(false);

const acceptAttr = taskTypeAccept('text.direct');

function resizeComposer() {
  const field = composerEl.value;
  if (!field) {
    return;
  }
  field.style.height = 'auto';
  field.style.height = `${field.scrollHeight}px`;
}

function resetForm() {
  instructions.value = '';
  inputFile.value = null;
  localError.value = '';
  if (fileInputEl.value) {
    fileInputEl.value.value = '';
  }
  void nextTick(resizeComposer);
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
  if (props.submitting || !validatePayload()) {
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

function onComposerKeydown(event) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    onSubmit();
  }
}
</script>

<template>
  <form
    class="task-submit-form"
    :class="composerOnly ? 'em-chat__composer-form' : 'em-chat__body'"
    @submit.prevent="onSubmit"
  >
    <div v-if="!composerOnly" class="em-chat__thread">
      <div class="em-chat__row">
        <span class="em-chat__avatar" aria-hidden="true">
          <span class="material-symbols-outlined">smart_toy</span>
        </span>
        <p class="em-chat__bubble em-chat__bubble--assistant">{{ t('tasks.chatGreeting') }}</p>
      </div>

      <div v-if="submitting && (instructions.trim() || inputFile)" class="em-chat__row em-chat__row--user">
        <p class="em-chat__bubble em-chat__bubble--user">
          <span v-if="instructions.trim()">{{ instructions.trim() }}</span>
          <span v-if="inputFile" class="em-chat__file">{{ inputFile.name }}</span>
        </p>
      </div>

      <div v-if="submitting" class="em-chat__row" aria-live="polite">
        <span class="em-chat__avatar" aria-hidden="true">
          <span class="material-symbols-outlined">smart_toy</span>
        </span>
        <p class="em-chat__bubble em-chat__bubble--assistant em-chat__typing">
          <span />
          <span />
          <span />
          <span class="visually-hidden">{{ t('tasks.submitting') }}</span>
        </p>
      </div>

      <p v-if="localError || error" class="md-alert md-alert--error" role="alert">
        {{ localError || error }}
      </p>
    </div>

    <div
      class="em-chat__dock"
      :class="{ 'em-chat__dock--active': dragOver }"
      @dragover.prevent="dragOver = true"
      @dragleave.prevent="dragOver = false"
      @drop="onDrop"
    >
      <p v-if="composerOnly && (localError || error)" class="md-alert md-alert--error" role="alert">
        {{ localError || error }}
      </p>
      <p v-if="inputFile" class="em-chat__attachment">
        <span class="material-symbols-outlined" aria-hidden="true">draft</span>
        {{ inputFile.name }}
        <button type="button" class="em-icon-btn" :aria-label="t('tasks.inputFileClear')" @click="clearFile">
          <span class="material-symbols-outlined" aria-hidden="true">close</span>
        </button>
      </p>
      <div class="em-chat__composer">
        <button
          type="button"
          class="em-chat__icon-btn"
          :aria-label="t('tasks.browseFiles')"
          :disabled="submitting"
          @click="browseFiles"
        >
          <span class="material-symbols-outlined" aria-hidden="true">attach_file</span>
        </button>
        <label class="visually-hidden" for="task-chat-input">{{ t('tasks.instructionsLabel') }}</label>
        <textarea
          id="task-chat-input"
          ref="composerEl"
          v-model="instructions"
          rows="1"
          :placeholder="t('tasks.chatPlaceholder')"
          :disabled="submitting"
          @input="resizeComposer"
          @keydown="onComposerKeydown"
        />
        <input
          ref="fileInputEl"
          type="file"
          class="visually-hidden"
          :accept="acceptAttr"
          :disabled="submitting"
          @change="onFileChange"
        />
        <button type="submit" class="em-chat__send" :aria-label="t('tasks.submitTask')" :disabled="submitting">
          <span v-if="submitting" class="md-spinner md-spinner--inline" aria-hidden="true" />
          <span v-else class="material-symbols-outlined" aria-hidden="true">send</span>
        </button>
      </div>
    </div>

    <button
      v-if="showCancel"
      type="button"
      class="visually-hidden"
      :disabled="submitting"
      @click="emit('cancel')"
    >
      {{ t('tasks.cancel') }}
    </button>
  </form>
</template>
