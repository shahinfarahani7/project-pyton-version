<script setup>
import { onMounted, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { t } from '../i18n';

const session = useSession();
const items = ref(null);

onMounted(() => {
  if (!session.hasPermission('customer.apikeys:read')) {
    return;
  }
  portalApi
    .apiKeys()
    .then((body) => {
      items.value = body;
    })
    .catch(() => {
      items.value = { items: [], page: { limit: 25, hasMore: false } };
    });
});
</script>

<template>
  <section class="panel">
    <h1>{{ t('nav.apiKeys') }}</h1>
    <p>API key secrets are shown once at creation and never stored in browser storage.</p>
    <table>
      <thead>
        <tr>
          <th scope="col">Key</th>
          <th scope="col">Status</th>
          <th scope="col">Version</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="item in items?.items ?? []" :key="item.id">
          <td>{{ item.id }}</td>
          <td>{{ item.status }}</td>
          <td>{{ item.version }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
