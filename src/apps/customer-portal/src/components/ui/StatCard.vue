<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: String, required: true },
  hint: { type: String, default: '' },
  icon: { type: String, default: 'insights' },
});
</script>

<template>
  <article class="stat-card">
    <div class="stat-card__icon" aria-hidden="true">
      <span class="material-symbols-outlined">{{ icon }}</span>
    </div>
    <div class="stat-card__body">
      <p class="stat-card__label">{{ label }}</p>
      <p class="stat-card__value">{{ value }}</p>
      <p v-if="hint" class="stat-card__hint">{{ hint }}</p>
    </div>
  </article>
</template>
