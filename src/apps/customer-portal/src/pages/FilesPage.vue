<script setup>
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';
import { formatBytes } from '../utils/format';

const files = [
  {
    id: 'fil_dev_invoice_batch',
    name: 'invoice-batch-q3.pdf',
    status: 'scanned',
    sizeBytes: 2_420_000,
    retentionDays: 90,
  },
  {
    id: 'fil_dev_model_weights',
    name: 'vision-model-v2.onnx',
    status: 'ready',
    sizeBytes: 48_900_000,
    retentionDays: 30,
  },
  {
    id: 'fil_dev_quarantine',
    name: 'unknown-upload.bin',
    status: 'quarantined',
    sizeBytes: 512_000,
    retentionDays: 7,
  },
];
</script>

<template>
  <section>
    <PageHeader :title="t('nav.files')" :subtitle="t('files.subtitle')">
      <template #actions>
        <button type="button" class="md-btn md-btn-filled" disabled>
          <span class="material-symbols-outlined" aria-hidden="true">upload_file</span>
          {{ t('files.upload') }}
        </button>
      </template>
    </PageHeader>

    <div class="upload-zone md-card">
      <span class="material-symbols-outlined" aria-hidden="true">cloud_upload</span>
      <p>{{ t('files.uploadHint') }}</p>
    </div>

    <article class="md-card">
      <PageHeader :title="t('files.libraryTitle')" />
      <div class="md-table-wrap">
        <table class="md-table">
          <thead>
            <tr>
              <th scope="col">{{ t('files.colName') }}</th>
              <th scope="col">{{ t('billing.status') }}</th>
              <th scope="col">{{ t('files.colSize') }}</th>
              <th scope="col">{{ t('files.colRetention') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="file in files" :key="file.id">
              <td>
                <span class="material-symbols-outlined" aria-hidden="true">description</span>
                {{ file.name }}
              </td>
              <td><StatusChip :status="file.status" /></td>
              <td>{{ formatBytes(file.sizeBytes) }}</td>
              <td>{{ file.retentionDays }}d</td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </section>
</template>
