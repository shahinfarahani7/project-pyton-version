<script setup>
import { computed } from 'vue';

import { statusTone } from '../../utils/format';

const props = defineProps({
  status: { type: String, required: true },
});

const tone = computed(() => statusTone(props.status));
</script>

<template>
  <span class="md-chip" :class="`md-chip--${tone}`">{{ status }}</span>
</template>
