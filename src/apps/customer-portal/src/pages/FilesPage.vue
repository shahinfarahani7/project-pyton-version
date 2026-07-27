<script setup>
import { t } from '../i18n';
</script>

<template>
  <section class="panel">
    <h1>{{ t('nav.files') }}</h1>
    <p>Upload intents and completed files use generated OpenAPI contracts with optimistic concurrency ETags.</p>
    <ul>
      <li>Malware scan status and retention policy surfaced per workspace.</li>
      <li>Download links are short-lived and never embed credentials.</li>
    </ul>
  </section>
</template>
