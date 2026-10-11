<script setup>
import markUrl from '../assets/brand/fibonai-mark.png';
import wordUrl from '../assets/brand/fibonai-wordmark.png';

defineProps({
  wordmark: { type: Boolean, default: true },
});
</script>

<template>
  <span class="fn-logo">
    <img class="fn-logo__mark" :src="markUrl" alt="" />
    <span v-if="wordmark || $slots.default" class="fn-logo__copy">
      <img v-if="wordmark" class="fn-logo__word" :src="wordUrl" alt="FibonAI" />
      <slot />
    </span>
  </span>
</template>
