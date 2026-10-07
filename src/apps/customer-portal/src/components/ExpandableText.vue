<script setup>
import { computed, ref } from 'vue';

import { t } from '../i18n';

const props = defineProps({
  text: { type: String, default: '' },
  previewChars: { type: Number, default: 500 },
  monospace: { type: Boolean, default: false },
});

const expanded = ref(false);
const copied = ref(false);

const normalized = computed(() => props.text ?? '');
const isLong = computed(() => normalized.value.length > props.previewChars);
const displayText = computed(() => {
  if (!isLong.value || expanded.value) {
    return normalized.value;
  }
  return `${normalized.value.slice(0, props.previewChars)}…`;
});

async function copyFull() {
  if (!normalized.value) {
    return;
  }
  await navigator.clipboard.writeText(normalized.value);
  copied.value = true;
  window.setTimeout(() => {
    copied.value = false;
  }, 1500);
}
</script>

<template>
  <div class="em-expandable-text">
    <pre
      v-if="monospace"
      class="em-expandable-text__body em-code-block"
      dir="auto"
    >{{ displayText }}</pre>
    <p
      v-else
      class="em-expandable-text__body em-task-detail-text"
      dir="auto"
    >{{ displayText }}</p>
    <div v-if="isLong || normalized" class="em-expandable-text__actions">
      <button
        v-if="isLong"
        type="button"
        class="md-btn md-btn-text em-expandable-text__btn"
        @click="expanded = !expanded"
      >
        {{ expanded ? t('tasks.showLess') : t('tasks.showFullText') }}
      </button>
      <button
        v-if="normalized"
        type="button"
        class="md-btn md-btn-text em-expandable-text__btn"
        @click="copyFull"
      >
        {{ copied ? t('tasks.copiedFullText') : t('tasks.copyFullText') }}
      </button>
    </div>
  </div>
</template>
