<script setup>
import { computed, ref } from 'vue';

import { opsApi } from '../api/client';
import { usePolling } from '../composables/polling';
import { formatFibon } from '../formatFibon';

const { data, error, updatedAt, refresh } = usePolling(() => opsApi.taskMonitor());

const statusFilter = ref('all');
const search = ref('');
const cancellingId = ref(null);
const actionError = ref(null);

const TERMINAL = new Set(['succeeded', 'failed', 'cancelled', 'expired']);
const DONE = new Set(['succeeded', 'completed', 'done']);

function lifecycle(task) {
  return String(task.lifecycleStatus ?? '').toLowerCase();
}

function canCancel(task) {
  return !TERMINAL.has(task.lifecycleStatus);
}

async function cancel(task) {
  if (!window.confirm(`Cancel ${task.id}? The worker will stop receiving it.`)) return;
  cancellingId.value = task.id;
  actionError.value = null;
  try {
    await opsApi.cancelTask(task.id);
    await refresh();
  } catch (err) {
    actionError.value = err?.message ?? 'Could not cancel task';
  } finally {
    cancellingId.value = null;
  }
}

const items = computed(() => data.value?.items ?? []);
const summary = computed(() => data.value?.summary ?? null);
const doneCount = computed(() => items.value.filter((task) => DONE.has(lifecycle(task))).length);
const failedCount = computed(() => items.value.filter((task) => lifecycle(task) === 'failed').length);
const uptimeLabel = computed(() => {
  const finished = doneCount.value + failedCount.value;
  if (finished === 0) return '—';
  const percent = Math.round((doneCount.value / finished) * 1000) / 10;
  return Number.isInteger(percent) ? `${percent}%` : `${percent.toFixed(1)}%`;
});
const statuses = computed(() => Object.keys(summary.value?.byStatus ?? {}).sort());

const filtered = computed(() => {
  const needle = search.value.trim().toLowerCase();
  return items.value.filter((task) => {
    if (statusFilter.value !== 'all' && lifecycle(task) !== statusFilter.value.toLowerCase()) return false;
    if (!needle) return true;
    const haystack = [task.id, task.taskType, ...task.devices.map((d) => `${d.deviceName ?? ''} ${d.deviceId} ${d.workerId ?? ''}`)]
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

function deviceLabel(device) {
  return device.deviceName || device.deviceId;
}

const pinnedDevice = computed(() => {
  const id = summary.value?.pinnedDeviceId;
  if (!id) return null;
  const known = items.value
    .flatMap((task) => task.devices ?? [])
    .find((device) => device.deviceId === id);
  return {
    id,
    name: summary.value?.pinnedDeviceName || known?.deviceName || null,
  };
});
</script>

<template>
  <section class="panel">
    <header class="page-header">
      <h1>Task monitor</h1>
      <span class="muted">Updated {{ updatedAt ? updatedAt.toLocaleTimeString() : '—' }}</span>
      <button type="button" class="ghost" @click="refresh">Refresh</button>
    </header>
    <p v-if="error" class="alert" role="alert">{{ error }}</p>
    <p v-if="actionError" class="alert" role="alert">{{ actionError }}</p>

    <div v-if="summary" class="stat-grid">
      <div class="stat"><span>Total</span><strong>{{ summary.total }}</strong></div>
      <div class="stat" data-stat="done"><span>Done</span><strong>{{ doneCount }}</strong></div>
      <div class="stat" data-stat="failed"><span>Failed</span><strong>{{ failedCount }}</strong></div>
      <div class="stat" data-stat="uptime"><span>Uptime</span><strong>{{ uptimeLabel }}</strong></div>
      <div class="stat"><span>Running on device</span><strong>{{ summary.running }}</strong></div>
      <div class="stat"><span>Waiting in worker queue</span><strong>{{ summary.queueDepth }}</strong></div>
      <div class="stat"><span>Failed deliveries</span><strong>{{ summary.failedDeliveries }}</strong></div>
      <div class="stat stat-wide">
        <span>Pinned device</span>
        <strong class="stat-text">{{ pinnedDevice?.name || pinnedDevice?.id || 'None' }}</strong>
        <small v-if="pinnedDevice?.name" class="mono">{{ pinnedDevice.id }}</small>
      </div>
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

    <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th scope="col">Task</th>
          <th scope="col">Tokens paid</th>
          <th scope="col">Type</th>
          <th scope="col">Workspace</th>
          <th scope="col">Status</th>
          <th scope="col">Device(s)</th>
          <th scope="col">Failure</th>
          <th scope="col">Created</th>
          <th scope="col">Updated</th>
          <th scope="col">Actions</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="task in filtered" :key="task.id">
          <td class="mono">{{ task.id }}</td>
          <td data-field="tokens-paid">{{ formatFibon(task.tokensGivenAtomic) }}</td>
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
                <strong>{{ deviceLabel(device) }}</strong>
                <span v-if="device.errorCode" class="error-text">{{ device.errorCode }}</span>
              </li>
            </ul>
          </td>
          <td class="error-text">{{ task.failureReasonCode ?? '' }}</td>
          <td>{{ time(task.createdAt) }}</td>
          <td>{{ time(task.updatedAt) }}</td>
          <td>
            <button
              v-if="canCancel(task)"
              type="button"
              class="danger"
              :disabled="cancellingId === task.id"
              @click="cancel(task)"
            >
              {{ cancellingId === task.id ? 'Cancelling…' : 'Cancel' }}
            </button>
          </td>
        </tr>
        <tr v-if="!filtered.length && !error">
          <td colspan="10" class="muted">No tasks match.</td>
        </tr>
      </tbody>
    </table>
    </div>
  </section>
</template>
