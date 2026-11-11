<script setup>
import { computed, ref } from 'vue';

import { opsApi } from '../api/client';
import { usePolling } from '../composables/polling';

const { data, error, updatedAt, refresh: load } = usePolling(() => opsApi.workerDevices(), 2_000);
const appFilter = ref('all');
const items = computed(() => data.value?.items ?? []);
const release = computed(() => data.value?.release ?? null);
const visibleItems = computed(() => {
  if (appFilter.value !== 'latest') return items.value;
  return items.value.filter((item) => item.appUpdated === true);
});

const ACTIVITY_LABELS = { busy: 'Running task', idle: 'Idle', unknown: 'Unknown' };
const PRESENCE_LABELS = { online: 'Online', offline: 'Offline', never_seen: 'Never seen' };

function presenceLabel(value) {
  return PRESENCE_LABELS[value] ?? value;
}

function seenAgo(iso) {
  if (!iso) return '—';
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return '—';
  const seconds = Math.max(0, Math.round((Date.now() - then) / 1000));
  if (seconds < 5) return 'just now';
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  return `${Math.floor(minutes / 60)}h ago`;
}

function liveCpu(item) {
  if (item.presence !== 'online') return '—';
  return cpuLabel(item.cpu ?? {});
}

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

function appLabel(item) {
  if (!item.appVersion && !item.appVersionCode) return '—';
  if (item.appVersion && item.appVersionCode) return `${item.appVersion} (${item.appVersionCode})`;
  return item.appVersion || String(item.appVersionCode);
}

function batteryLabel(battery) {
  const level = percent(battery.levelBps);
  return battery.charging ? `${level} (charging)` : level;
}

</script>

<template>
  <section class="panel">
    <div class="page-header">
      <h1>Workers</h1>
      <p class="muted">Live every 2s<span v-if="updatedAt"> · {{ seenAgo(updatedAt.toISOString()) }}</span></p>
      <button type="button" class="ghost" @click="load">Refresh</button>
    </div>
    <p v-if="error" class="alert" role="alert">{{ error }}</p>

    <div class="filters">
      <label>
        App
        <select v-model="appFilter">
          <option value="all">All devices</option>
          <option value="latest">Latest update</option>
        </select>
      </label>
      <p v-if="release" class="muted">Published build {{ release.versionName }} ({{ release.versionCode }})</p>
      <p v-else class="muted">No published app build to compare.</p>
    </div>

    <div class="table-wrap">
    <table data-table="workers">
      <thead>
        <tr>
          <th scope="col">Device</th>
          <th scope="col">Device ID</th>
          <th scope="col">Worker</th>
          <th scope="col">Registration</th>
          <th scope="col">App</th>
          <th scope="col">Presence</th>
          <th scope="col">Task</th>
          <th scope="col">CPU usage</th>
          <th scope="col">RAM (free / total)</th>
          <th scope="col">Battery</th>
          <th scope="col">Last heartbeat</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="item in visibleItems" :key="item.id" :data-activity="item.activity">
          <td class="device-name">
            <strong>{{ item.device?.name ?? 'Unknown device' }}</strong>
            <small v-if="deviceDetail(item)">{{ deviceDetail(item) }}</small>
          </td>
          <td class="mono">{{ item.id }}</td>
          <td class="mono">{{ item.workerId }}</td>
          <td>{{ item.status }}</td>
          <td>{{ appLabel(item) }}</td>
          <td><span class="pill" :data-presence="item.presence">{{ presenceLabel(item.presence) }}</span></td>
          <td>{{ ACTIVITY_LABELS[item.activity] ?? item.activity }}</td>
          <td>{{ liveCpu(item) }}</td>
          <td>{{ gib(item.ram.freeBytes) }} / {{ gib(item.ram.totalBytes) }}</td>
          <td>{{ batteryLabel(item.battery) }}</td>
          <td>{{ seenAgo(item.lastHeartbeatAt) }}</td>
        </tr>
        <tr v-if="!visibleItems.length && !error">
          <td colspan="11">{{ appFilter === 'latest' ? 'No devices on the latest update.' : 'No workers registered.' }}</td>
        </tr>
      </tbody>
    </table>
    </div>
  </section>
</template>
