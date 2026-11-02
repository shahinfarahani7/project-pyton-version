<script setup>
import { computed } from 'vue';

import { opsApi } from '../api/client';
import { usePolling } from '../composables/polling';

const { data, error, refresh: load } = usePolling(() => opsApi.workerDevices());
const items = computed(() => data.value?.items ?? []);

const ACTIVITY_LABELS = { busy: 'Running task', idle: 'Idle', unknown: 'Unknown' };

function percent(bps) {
  return bps === null || bps === undefined ? '—' : `${(bps / 100).toFixed(0)}%`;
}

function gib(bytes) {
  return bytes === null || bytes === undefined ? '—' : `${(bytes / 1024 ** 3).toFixed(1)} GB`;
}

function cpuLabel(cpu) {
  const usage = cpu.usageBps === null || cpu.usageBps === undefined ? 'not reported' : `${percent(cpu.usageBps)} used`;
  return cpu.cores ? `${cpu.cores} cores · ${usage}` : usage;
}

function deviceDetail(item) {
  const device = item.device ?? {};
  return [device.model && device.model !== device.name ? device.model : null, item.platform]
    .filter(Boolean)
    .join(' · ');
}

function batteryLabel(battery) {
  const level = percent(battery.levelBps);
  return battery.charging ? `${level} (charging)` : level;
}

</script>

<template>
  <section class="panel">
    <h1>Workers</h1>
    <button type="button" @click="load">Refresh</button>
    <p v-if="error" role="alert">{{ error }}</p>
    <table>
      <thead>
        <tr>
          <th scope="col">Device</th>
          <th scope="col">Device ID</th>
          <th scope="col">Worker</th>
          <th scope="col">Status</th>
          <th scope="col">Presence</th>
          <th scope="col">Task</th>
          <th scope="col">CPU usage</th>
          <th scope="col">RAM (free / total)</th>
          <th scope="col">Battery</th>
          <th scope="col">Last heartbeat</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="item in items" :key="item.id" :data-activity="item.activity">
          <td class="device-name">
            <strong>{{ item.device?.name ?? 'Unknown device' }}</strong>
            <small v-if="deviceDetail(item)">{{ deviceDetail(item) }}</small>
          </td>
          <td>{{ item.id }}</td>
          <td>{{ item.workerId }}</td>
          <td>{{ item.status }}</td>
          <td>{{ item.presence }}</td>
          <td>{{ ACTIVITY_LABELS[item.activity] ?? item.activity }}</td>
          <td>{{ cpuLabel(item.cpu) }}</td>
          <td>{{ gib(item.ram.freeBytes) }} / {{ gib(item.ram.totalBytes) }}</td>
          <td>{{ batteryLabel(item.battery) }}</td>
          <td>{{ item.lastHeartbeatAt ?? '—' }}</td>
        </tr>
        <tr v-if="!items.length && !error">
          <td colspan="10">No workers registered.</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
