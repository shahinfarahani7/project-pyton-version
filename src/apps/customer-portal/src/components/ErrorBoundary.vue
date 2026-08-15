<script setup>
import { onErrorCaptured, ref } from 'vue';

import { t } from '../i18n';
import { trackEvent } from '../telemetry';

const hasError = ref(false);
const errorMessage = ref('');

onErrorCaptured((error, _instance, info) => {
  hasError.value = true;
  errorMessage.value = error instanceof Error ? error.message : String(error);
  trackEvent('portal.error.boundary', { message: errorMessage.value, componentStack: info });
  return false;
});
</script>

<template>
  <section v-if="hasError" role="alert" class="panel error-panel">
    <h1>{{ t('error.boundary') }}</h1>
    <p>{{ errorMessage || t('error.sessionExpired') }}</p>
  </section>
  <slot v-else />
</template>
