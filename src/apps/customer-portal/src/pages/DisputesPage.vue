<script setup>
import { onMounted, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { t } from '../i18n';

const session = useSession();
const items = ref(null);

onMounted(() => {
  if (!session.workspaceId || !session.hasPermission('customer.billing:read')) {
    return;
  }
  portalApi
    .disputes(session.workspaceId)
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
    <h1>{{ t('nav.disputes') }}</h1>
    <table>
      <thead>
        <tr>
          <th scope="col">Dispute</th>
          <th scope="col">Status</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="item in items?.items ?? []" :key="item.id">
          <td>{{ item.id }}</td>
          <td>{{ item.status }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
