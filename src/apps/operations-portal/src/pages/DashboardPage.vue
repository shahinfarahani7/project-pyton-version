<script setup>
import { computed } from 'vue';
import { RouterLink } from 'vue-router';

import { opsApi } from '../api/client';
import { useSession } from '../auth/session';
import { usePolling } from '../composables/polling';

const session = useSession();
const { data, error, updatedAt } = usePolling(() => opsApi.overview());

const workers = computed(() => data.value?.workers ?? null);
const tasks = computed(() => data.value?.tasks ?? null);

const alerts = computed(() => {
  const list = [];
  if (data.value?.tasksError) list.push(`Task data unavailable: ${data.value.tasksError}`);
  if (workers.value?.lowBattery) list.push(`${workers.value.lowBattery} online device(s) below 20% battery and not charging`);
  if (workers.value?.hotDevices) list.push(`${workers.value.hotDevices} online device(s) overheating`);
  if (tasks.value?.failedDeliveries) list.push(`${tasks.value.failedDeliveries} failed task deliveries`);
  if (workers.value && !workers.value.byPresence.online && (tasks.value?.queueDepth ?? 0) > 0) {
    list.push('Tasks are waiting but no worker is online');
  }
  return list;
});

function count(group, key) {
  return group?.[key] ?? 0;
}
</script>

<template>
  <section class="panel">
    <header class="page-header">
      <h1>Operations overview</h1>
      <span class="muted">Updated {{ updatedAt ? updatedAt.toLocaleTimeString() : '—' }}</span>
    </header>
    <p v-if="error" class="alert" role="alert">{{ error }}</p>

    <ul v-if="alerts.length" class="alert-list" aria-label="Alerts">
      <li v-for="alert in alerts" :key="alert">{{ alert }}</li>
    </ul>

    <h2>Workers</h2>
    <div v-if="workers" class="stat-grid">
      <RouterLink class="stat" to="/workers"><span>Registered</span><strong>{{ workers.total }}</strong></RouterLink>
      <div class="stat"><span>Online</span><strong>{{ count(workers.byPresence, 'online') }}</strong></div>
      <div class="stat"><span>Running a task</span><strong>{{ count(workers.byActivity, 'busy') }}</strong></div>
      <div class="stat"><span>Idle</span><strong>{{ count(workers.byActivity, 'idle') }}</strong></div>
      <div class="stat">
        <span>Offline / never seen</span>
        <strong>{{ count(workers.byPresence, 'offline') + count(workers.byPresence, 'never_seen') }}</strong>
      </div>
    </div>

    <h2>Tasks</h2>
    <div v-if="tasks" class="stat-grid">
      <RouterLink class="stat" to="/tasks"><span>Total</span><strong>{{ tasks.total }}</strong></RouterLink>
      <div class="stat"><span>Running on device</span><strong>{{ tasks.running }}</strong></div>
      <div class="stat"><span>Waiting in queue</span><strong>{{ tasks.queueDepth }}</strong></div>
      <div v-for="(value, status) in tasks.byStatus" :key="status" class="stat">
        <span>{{ status }}</span><strong>{{ value }}</strong>
      </div>
    </div>

    <h2>Session</h2>
    <dl>
      <dt>Operator</dt>
      <dd>{{ session.operatorId }}</dd>
      <dt>Role</dt>
      <dd>{{ session.role }}</dd>
    </dl>
  </section>
</template>
