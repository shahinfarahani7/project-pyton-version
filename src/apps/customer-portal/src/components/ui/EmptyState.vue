<script setup>
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  icon: { type: String, default: 'inbox' },
});
</script>

<template>
  <div class="empty-state">
    <span class="material-symbols-outlined empty-state__icon" aria-hidden="true">{{ icon }}</span>
    <h2>{{ title }}</h2>
    <p v-if="description">{{ description }}</p>
  </div>
</template>
