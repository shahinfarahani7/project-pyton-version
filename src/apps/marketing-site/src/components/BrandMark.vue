<script setup>
defineProps({
  size: { type: Number, default: 28 },
});
</script>

<template>
  <svg
    class="brand-mark"
    :width="size"
    :height="Math.round((size * 248) / 266)"
    viewBox="0 0 266 248"
    fill="none"
    aria-hidden="true"
    focusable="false"
  >
    <g class="brand-mark__line" stroke="currentColor" stroke-width="22.5" stroke-linecap="butt" stroke-linejoin="miter">
      <path d="M143 11.25H11.25V236.75H168V182" />
      <path d="M168 132V11.25H254.75V157H47V85A38 38 0 0 1 85 47" />
    </g>
    <g class="brand-mark__gold">
      <path d="M73 132V105A70 70 0 0 1 143 35V132Z" />
      <rect x="193" y="35" width="36" height="97" />
    </g>
  </svg>
</template>
