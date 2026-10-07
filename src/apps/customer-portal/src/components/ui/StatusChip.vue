<script setup>
import { computed } from 'vue';

import { statusTone } from '../../utils/format';

const props = defineProps({
  status: { type: String, required: true },
  label: { type: String, default: '' },
});

const tone = computed(() => statusTone(props.status));
</script>

<template>
  <span class="md-chip" :class="`md-chip--${tone}`">{{ label || status }}</span>
</template>
