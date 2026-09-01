<script setup>
defineProps({
  label: { type: String, default: '' },
});
</script>

<template>
  <div class="section-divider" aria-hidden="true">
    <span class="section-divider__line" />
    <span v-if="label" class="section-divider__label">{{ label }}</span>
    <span class="section-divider__dot section-divider__dot--a" />
    <span class="section-divider__dot section-divider__dot--b" />
    <span class="section-divider__line" />
  </div>
</template>
