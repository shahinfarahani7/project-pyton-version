<script setup>
import { onMounted, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

const session = useSession();
const tasks = ref(null);
const error = ref(null);

onMounted(() => {
  if (!session.workspaceId || !session.hasPermission('customer.tasks:read')) {
    return;
  }
  trackEvent('portal.page.tasks');
  portalApi
    .tasks(session.workspaceId)
    .then((body) => {
      tasks.value = body;
    })
    .catch((err) => {
      error.value = err.message;
    });
});
</script>

<template>
  <section class="panel">
    <h1>{{ t('nav.tasks') }}</h1>
    <p v-if="error" role="alert">{{ error }}</p>
    <table>
      <caption class="visually-hidden">Task list</caption>
      <thead>
        <tr>
          <th scope="col">Task ID</th>
          <th scope="col">Type</th>
          <th scope="col">Lifecycle</th>
          <th scope="col">Execution</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="task in tasks?.items ?? []" :key="task.id">
          <td>{{ task.id }}</td>
          <td>{{ task.taskType }}</td>
          <td>{{ task.lifecycleStatus }}</td>
          <td>{{ task.executionStatus }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
