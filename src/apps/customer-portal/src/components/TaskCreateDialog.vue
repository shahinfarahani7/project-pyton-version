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
  <dialog ref="dialogEl" class="md-dialog" @close="onCancel">
    <div class="md-dialog__panel md-card" :class="{ 'md-dialog__panel--busy': submitting }">
      <div v-if="submitting" class="md-dialog__busy" aria-live="polite">
        <span class="md-spinner" aria-hidden="true" />
        <span>{{ t('tasks.submitting') }}</span>
      </div>
      <header class="md-dialog__header">
        <h2 class="page-title">{{ t('tasks.createTitle') }}</h2>
        <p class="page-subtitle">{{ t('tasks.createSubtitle') }}</p>
      </header>
      <TaskSubmitForm
        :key="formKey"
        :reset-key="formKey"
        :submitting="submitting"
        :error="error"
        show-cancel
        @submit="emit('submit', $event)"
        @cancel="onCancel"
      />
    </div>
  </dialog>
</template>
