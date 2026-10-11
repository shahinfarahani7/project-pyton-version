<script setup>
import StrokeIcon from './StrokeIcon.vue';

defineProps({
  label: { type: String, required: true },
  value: { type: String, required: true },
  hint: { type: String, default: '' },
  icon: { type: String, default: 'chart' },
});
</script>

<template>
  <article class="stat-card">
    <div class="stat-card__top">
      <p class="stat-card__label">{{ label }}</p>
      <StrokeIcon :name="icon" />
    </div>
    <p class="stat-card__value">{{ value }}</p>
    <p v-if="hint" class="stat-card__hint">{{ hint }}</p>
  </article>
</template>
