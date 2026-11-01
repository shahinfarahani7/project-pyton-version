<script setup>
import { computed, ref, watch } from 'vue';
import { portalApi } from '../api/client';
import { resolveLocale, t } from '../i18n';

const props = defineProps({
  keys: { type: Array, default: () => [] },
});

const ranges = ['day', 'week', 'month', '6m'];
const range = ref('week');
const selectedKey = ref('all');
const usage = ref(null);
const loading = ref(false);
const error = ref('');
const hovered = ref(-1);

const locale = resolveLocale() === 'fa' ? 'fa-IR' : 'en-US';
const numberFormat = new Intl.NumberFormat(locale);

async function load() {
  loading.value = true;
  error.value = '';
  try {
    usage.value = await portalApi.apiKeyUsage(range.value);
  } catch (err) {
    error.value = err?.message || t('apiKeys.usageLoadError');
  } finally {
    loading.value = false;
  }
}

watch(range, load, { immediate: true });

const keyNames = computed(() => Object.fromEntries(props.keys.map((item) => [item.id, item.name || item.id])));

const rows = computed(() => {
  const all = usage.value?.items ?? [];
  const filtered = selectedKey.value === 'all' ? all : all.filter((row) => row.keyId === selectedKey.value);
  return [...filtered].sort((a, b) => b.rangeRequests - a.rangeRequests);
});

const totals = computed(() =>
  rows.value.reduce(
    (acc, row) => ({
      requests: acc.requests + row.rangeRequests,
      tasks: acc.tasks + row.rangeTasks,
      errors: acc.errors + row.rangeErrors,
    }),
    { requests: 0, tasks: 0, errors: 0 },
  ),
);

const successRate = computed(() => {
  if (!totals.value.requests) {
    return '—';
  }
  const rate = ((totals.value.requests - totals.value.errors) / totals.value.requests) * 100;
  return `${numberFormat.format(Math.round(rate))}%`;
});

const kpis = computed(() => [
  { id: 'requests', icon: 'swap_vert', label: t('apiKeys.usageRequests'), value: numberFormat.format(totals.value.requests) },
  { id: 'tasks', icon: 'task_alt', label: t('apiKeys.usageTasks'), value: numberFormat.format(totals.value.tasks) },
  { id: 'errors', icon: 'block', label: t('apiKeys.usageErrorsCol'), value: numberFormat.format(totals.value.errors) },
  { id: 'rate', icon: 'verified', label: t('apiKeys.usageSuccessRate'), value: successRate.value },
]);

const series = computed(() => {
  const buckets = usage.value?.buckets ?? [];
  const values = buckets.map(() => 0);
  for (const row of rows.value) {
    row.series.forEach((value, index) => {
      values[index] += value;
    });
  }
  return values;
});

const chartWidth = 720;
const chartHeight = 180;
const chartMax = computed(() => {
  const peak = Math.max(1, ...series.value);
  const magnitude = 10 ** Math.floor(Math.log10(peak));
  return Math.ceil(peak / magnitude) * magnitude;
});
const gridLines = computed(() => [0, 0.25, 0.5, 0.75, 1].map((ratio) => ({ ratio, value: Math.round(chartMax.value * ratio) })));
const slot = computed(() => (series.value.length ? chartWidth / series.value.length : chartWidth));
const barWidth = computed(() => Math.max(2, slot.value * 0.62));

function barHeight(value) {
  return (value / chartMax.value) * chartHeight;
}

function bucketLabel(iso) {
  if (!iso) {
    return '';
  }
  const date = new Date(iso);
  if (range.value === 'day') {
    return date.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' });
  }
  return date.toLocaleDateString(locale, { month: 'short', day: 'numeric' });
}

const axisLabels = computed(() => {
  const buckets = usage.value?.buckets ?? [];
  if (!buckets.length) {
    return [];
  }
  const step = Math.max(1, Math.ceil(buckets.length / 6));
  return buckets
    .map((iso, index) => ({ index, label: bucketLabel(iso) }))
    .filter((item) => item.index % step === 0);
});

const tooltip = computed(() => {
  if (hovered.value < 0 || !usage.value) {
    return null;
  }
  return {
    label: bucketLabel(usage.value.buckets[hovered.value]),
    value: numberFormat.format(series.value[hovered.value] ?? 0),
    left: `${((hovered.value + 0.5) / series.value.length) * 100}%`,
  };
});

function formatDateTime(iso) {
  return iso ? new Date(iso).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' }) : '—';
}

function share(row) {
  return totals.value.requests ? (row.rangeRequests / totals.value.requests) * 100 : 0;
}
</script>

<template>
  <article class="md-card em-usage">
    <header class="em-usage__head">
      <div class="em-apikeys-section-head">
        <span class="em-apikeys-section-head__icon material-symbols-outlined" aria-hidden="true">monitoring</span>
        <div>
          <h2>{{ t('apiKeys.usageStatsTitle') }}</h2>
          <p>{{ t('apiKeys.usageStatsSubtitle') }}</p>
        </div>
      </div>
      <div class="em-usage__filters">
        <select v-model="selectedKey" class="md-input em-usage__select" :aria-label="t('apiKeys.usageKeyFilter')">
          <option value="all">{{ t('apiKeys.usageAllKeys') }}</option>
          <option v-for="item in keys" :key="item.id" :value="item.id">{{ item.name || item.id }}</option>
        </select>
        <div class="em-segmented" role="tablist">
          <button
            v-for="item in ranges"
            :key="item"
            type="button"
            role="tab"
            :aria-selected="range === item"
            :class="{ 'is-active': range === item }"
            @click="range = item"
          >
            {{ t(`apiKeys.usageRange.${item}`) }}
          </button>
        </div>
      </div>
    </header>

    <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>

    <template v-else>
      <div class="em-usage__kpis">
        <div v-for="item in kpis" :key="item.id" class="em-usage__kpi" :class="`em-usage__kpi--${item.id}`">
          <span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span>
          <div>
            <small>{{ item.label }}</small>
            <strong>{{ loading && !usage ? '…' : item.value }}</strong>
          </div>
        </div>
      </div>

      <div class="em-usage__chart-wrap" :class="{ 'is-loading': loading }" dir="ltr">
        <div class="em-usage__yaxis">
          <span v-for="line in [...gridLines].reverse()" :key="line.ratio">{{ numberFormat.format(line.value) }}</span>
        </div>
        <div class="em-usage__plot" @mouseleave="hovered = -1">
          <svg
            class="em-usage__chart"
            :viewBox="`0 0 ${chartWidth} ${chartHeight}`"
            preserveAspectRatio="none"
            role="img"
            :aria-label="t('apiKeys.usageChart')"
          >
            <defs>
              <linearGradient id="em-usage-bar" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="#cdae6f" />
                <stop offset="100%" stop-color="#cdae6f" stop-opacity="0.35" />
              </linearGradient>
            </defs>
            <line
              v-for="line in gridLines"
              :key="line.ratio"
              x1="0"
              :x2="chartWidth"
              :y1="chartHeight - line.ratio * chartHeight"
              :y2="chartHeight - line.ratio * chartHeight"
              class="em-usage__grid"
            />
            <rect
              v-for="(value, index) in series"
              :key="`hit-${index}`"
              :x="index * slot"
              y="0"
              :width="slot"
              :height="chartHeight"
              class="em-usage__hit"
              :class="{ 'is-hovered': hovered === index }"
              @mouseenter="hovered = index"
            />
            <rect
              v-for="(value, index) in series"
              :key="`bar-${index}`"
              :x="index * slot + (slot - barWidth) / 2"
              :y="chartHeight - barHeight(value)"
              :width="barWidth"
              :height="barHeight(value)"
              rx="3"
              class="em-usage__bar"
            />
          </svg>
          <div v-if="tooltip" class="em-usage__tooltip" :style="{ left: tooltip.left }">
            <small>{{ tooltip.label }}</small>
            <strong>{{ tooltip.value }}</strong>
          </div>
          <div class="em-usage__xaxis">
            <span
              v-for="item in axisLabels"
              :key="item.index"
              :style="{ left: `${((item.index + 0.5) / series.length) * 100}%` }"
            >{{ item.label }}</span>
          </div>
          <p v-if="!loading && !totals.requests" class="em-usage__empty">{{ t('apiKeys.usageEmpty') }}</p>
        </div>
      </div>

      <div v-if="rows.length" class="em-usage__table">
        <table>
          <thead>
            <tr>
              <th>{{ t('apiKeys.name') }}</th>
              <th>{{ t('apiKeys.usageRequests') }}</th>
              <th>{{ t('apiKeys.usageTasks') }}</th>
              <th>{{ t('apiKeys.usageErrorsCol') }}</th>
              <th>{{ t('apiKeys.usageTotal') }}</th>
              <th>{{ t('apiKeys.usageLastUsed') }}</th>
              <th>{{ t('apiKeys.usageLastIp') }}</th>
              <th>{{ t('apiKeys.usageCost') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.keyId">
              <td>
                <div class="em-usage__keycell">
                  <strong>{{ keyNames[row.keyId] || row.keyId }}</strong>
                  <span class="em-usage__share"><span :style="{ width: `${share(row)}%` }" /></span>
                </div>
              </td>
              <td class="is-num">{{ numberFormat.format(row.rangeRequests) }}</td>
              <td class="is-num">{{ numberFormat.format(row.rangeTasks) }}</td>
              <td class="is-num" :class="{ 'is-error': row.rangeErrors }">{{ numberFormat.format(row.rangeErrors) }}</td>
              <td class="is-num">{{ numberFormat.format(row.totalRequests) }} / {{ numberFormat.format(row.totalTasks) }}</td>
              <td>{{ formatDateTime(row.lastUsedAt) }}</td>
              <td><code dir="ltr">{{ row.lastIp || '—' }}</code></td>
              <td><span class="md-chip md-chip--neutral" :title="t('apiKeys.usageCostPending')">—</span></td>
            </tr>
          </tbody>
        </table>
      </div>
      <small class="em-usage__note">
        <span class="material-symbols-outlined" aria-hidden="true">info</span>
        {{ t('apiKeys.usageNote') }}
      </small>
    </template>
  </article>
</template>
