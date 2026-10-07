<script setup>
import { ref, watch } from 'vue';

import TaskSubmitForm from './TaskSubmitForm.vue';
import { t } from '../i18n';

const props = defineProps({
  open: { type: Boolean, default: false },
  formKey: { type: Number, default: 0 },
  submitting: { type: Boolean, default: false },
  error: { type: String, default: '' },
});

const emit = defineEmits(['close', 'submit']);

const dialogEl = ref(null);

watch(
  () => props.open,
  (open) => {
    if (open) {
      dialogEl.value?.showModal();
      return;
    }
    dialogEl.value?.close();
  },
);

function onCancel() {
  emit('close');
}
</script>

<template>
  <dialog ref="dialogEl" class="md-dialog md-dialog--chat" @close="onCancel">
    <div class="md-dialog__panel md-card em-chat" :class="{ 'md-dialog__panel--busy': submitting }">
      <header class="em-chat__header">
        <span class="em-chat__avatar" aria-hidden="true">
          <span class="material-symbols-outlined">smart_toy</span>
        </span>
        <div class="em-chat__title">
          <h2>{{ t('tasks.createTitle') }}</h2>
          <p>{{ submitting ? t('tasks.submitting') : t('app.title') }}</p>
        </div>
        <button type="button" class="em-icon-btn" :aria-label="t('tasks.cancel')" @click="onCancel">
          <span class="material-symbols-outlined" aria-hidden="true">close</span>
        </button>
      </header>
      <TaskSubmitForm
        :key="formKey"
        :reset-key="formKey"
        :submitting="submitting"
        :error="error"
        @submit="emit('submit', $event)"
        @cancel="onCancel"
      />
    </div>
  </dialog>
</template>
