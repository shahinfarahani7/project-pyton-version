<script setup>
import { computed, ref } from 'vue';

import { opsApi } from '../api/client';
import { usePolling } from '../composables/polling';

const { data, error, updatedAt, refresh } = usePolling(() => opsApi.taskMonitor());

const statusFilter = ref('all');
const search = ref('');

const items = computed(() => data.value?.items ?? []);
const summary = computed(() => data.value?.summary ?? null);
const statuses = computed(() => Object.keys(summary.value?.byStatus ?? {}).sort());

const filtered = computed(() => {
  const needle = search.value.trim().toLowerCase();
  return items.value.filter((task) => {
    if (statusFilter.value !== 'all' && task.lifecycleStatus !== statusFilter.value) return false;
    if (!needle) return true;
    const haystack = [task.id, task.taskType, ...task.devices.map((d) => `${d.deviceId} ${d.workerId ?? ''}`)]
      .join(' ')
      .toLowerCase();
    return haystack.includes(needle);
  });
});

function time(value) {
  return value ? new Date(value).toLocaleString() : '—';
}

function short(value) {
  return value ? String(value).slice(0, 8) : '—';
}
</script>

<template>
  <section class="panel">
    <header class="page-header">
      <h1>Task monitor</h1>
      <span class="muted">Updated {{ updatedAt ? updatedAt.toLocaleTimeString() : '—' }}</span>
      <button type="button" @click="refresh">Refresh</button>
    </header>
    <p v-if="error" class="alert" role="alert">{{ error }}</p>

    <div v-if="summary" class="stat-grid">
      <div class="stat"><span>Total</span><strong>{{ summary.total }}</strong></div>
      <div class="stat"><span>Running on device</span><strong>{{ summary.running }}</strong></div>
      <div class="stat"><span>Waiting in worker queue</span><strong>{{ summary.queueDepth }}</strong></div>
      <div class="stat"><span>Failed deliveries</span><strong>{{ summary.failedDeliveries }}</strong></div>
      <div class="stat"><span>Pinned device</span><strong class="mono">{{ summary.pinnedDeviceId ?? 'none' }}</strong></div>
    </div>

    <div class="filters">
      <label>
        Status
        <select v-model="statusFilter">
          <option value="all">All</option>
          <option v-for="status in statuses" :key="status" :value="status">{{ status }}</option>
        </select>
      </label>
      <label>
        Search
        <input v-model="search" placeholder="Task, type, device or worker ID" />
      </label>
    </div>

    <table>
      <thead>
        <tr>
          <th scope="col">Task</th>
          <th scope="col">Type</th>
          <th scope="col">Workspace</th>
          <th scope="col">Status</th>
          <th scope="col">Device(s)</th>
          <th scope="col">Failure</th>
          <th scope="col">Created</th>
          <th scope="col">Updated</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="task in filtered" :key="task.id">
          <td class="mono">{{ task.id }}</td>
          <td>{{ task.taskType }}</td>
          <td class="mono" :title="task.workspaceId">{{ short(task.workspaceId) }}</td>
          <td>
            <span class="pill" :data-status="task.lifecycleStatus">{{ task.lifecycleStatus }}</span>
            <span v-if="task.executionStatus && task.executionStatus !== task.lifecycleStatus" class="muted">
              / {{ task.executionStatus }}
            </span>
          </td>
          <td>
            <span v-if="!task.devices.length" class="muted">
              {{ task.inWorkerQueue ? 'Waiting for a device' : 'Not delivered' }}
            </span>
            <ul v-else class="device-list">
              <li v-for="device in task.devices" :key="device.deviceId">
                <span class="mono">{{ device.deviceId }}</span>
                <span class="pill" :data-status="device.state">{{ device.state }}</span>
                <span v-if="device.workerId" class="muted">{{ device.workerId }} · {{ device.platform }} · {{ device.deviceTier }}</span>
                <span v-if="device.errorCode" class="error-text">{{ device.errorCode }}</span>
                <span class="muted">at {{ time(device.deliveredAt) }}</span>
              </li>
            </ul>
          </td>
          <td class="error-text">{{ task.failureReasonCode ?? '' }}</td>
          <td>{{ time(task.createdAt) }}</td>
          <td>{{ time(task.updatedAt) }}</td>
        </tr>
        <tr v-if="!filtered.length && !error">
          <td colspan="8" class="muted">No tasks match.</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
