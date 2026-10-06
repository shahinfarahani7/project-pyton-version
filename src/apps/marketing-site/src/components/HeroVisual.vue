<script setup>
import { onMounted, onUnmounted, ref } from 'vue';

const events = [
  { mark: '✓', title: 'quote locked', detail: '€0.0025' },
  { mark: '◉', title: 'worker assigned', detail: 'edge' },
  { mark: '✓', title: 'ocr verified', detail: 'document.ocr' },
  { mark: '⛨', title: 'audit written', detail: 'ledger' },
  { mark: '◈', title: 'fallback logged', detail: 'recorded' },
  { mark: '✓', title: 'result delivered', detail: 'webhook' },
];

const chips = ref(events.slice(0, 3));
let timer = 0;
let cursor = 3;

onMounted(() => {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  timer = window.setInterval(() => {
    const slot = cursor % chips.value.length;
    const next = chips.value.slice();
    next[slot] = events[cursor % events.length];
    chips.value = next;
    cursor += 1;
  }, 2600);
});

onUnmounted(() => {
  window.clearInterval(timer);
});
</script>

<template>
  <ul class="command-chips" aria-label="Live task status">
    <li v-for="chip in chips" :key="`${chip.title}-${chip.detail}`" class="command-chips__item">
      <span class="command-chips__mark" aria-hidden="true">{{ chip.mark }}</span>
      <strong>{{ chip.title }}</strong>
      <span>{{ chip.detail }}</span>
    </li>
  </ul>
</template>
