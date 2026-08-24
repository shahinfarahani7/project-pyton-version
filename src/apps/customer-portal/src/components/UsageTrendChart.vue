<script setup>
import { computed, ref } from 'vue';

import { resolveLocale, t } from '../i18n';
import { buildLineChartModel } from '../utils/chartHelpers';
import { formatNumber } from '../utils/format';

const props = defineProps({
  taskItems: {
    type: Array,
    default: () => [],
  },
});

const hoverIndex = ref(null);
const chartRef = ref(null);

const model = computed(() => buildLineChartModel(props.taskItems, resolveLocale()));
const activePoint = computed(() =>
  hoverIndex.value == null ? null : model.value.points[hoverIndex.value] ?? null,
);

function formatAverage(value) {
  return value >= 10 ? Math.round(value).toString() : value.toFixed(1);
}

function onPointerMove(event) {
  const svg = chartRef.value;
  if (!svg || !model.value.points.length) {
    return;
  }
  const rect = svg.getBoundingClientRect();
  const scaleX = model.value.plot.viewWidth / rect.width;
  const pointerX = (event.clientX - rect.left) * scaleX;
  let nearest = 0;
  let nearestDistance = Number.POSITIVE_INFINITY;
  for (const point of model.value.points) {
    const distance = Math.abs(point.x - pointerX);
    if (distance < nearestDistance) {
      nearest = point.index;
      nearestDistance = distance;
    }
  }
  hoverIndex.value = nearest;
}

function onPointerLeave() {
  hoverIndex.value = null;
}
</script>

<template>
  <article class="md-card em-chart-card em-usage-trend">
    <div class="em-chart-card__header">
      <div>
        <h2 class="em-section-title">{{ t('dashboard.usageTrend') }}</h2>
        <p class="em-chart-card__summary">
          {{ t('dashboard.usageTrendLast7Days') }}
          <span v-if="model.isEstimated" class="em-chart-card__note">
            · {{ t('dashboard.usageTrendEstimated') }}
          </span>
        </p>
      </div>
    </div>

    <div class="em-usage-trend__stats">
      <div class="em-usage-trend__stat">
        <span class="em-usage-trend__stat-label">{{ t('dashboard.usageTrendTotal') }}</span>
        <strong class="em-usage-trend__stat-value">{{ formatNumber(model.total) }}</strong>
      </div>
      <div class="em-usage-trend__stat">
        <span class="em-usage-trend__stat-label">{{ t('dashboard.usageTrendAverage') }}</span>
        <strong class="em-usage-trend__stat-value">{{ formatAverage(model.average) }}</strong>
      </div>
      <div class="em-usage-trend__stat">
        <span class="em-usage-trend__stat-label">{{ t('dashboard.usageTrendPeak') }}</span>
        <strong class="em-usage-trend__stat-value">{{ formatNumber(model.peak) }}</strong>
      </div>
    </div>

    <div class="em-usage-trend__canvas">
      <svg
        ref="chartRef"
        class="em-line-chart"
        :viewBox="`0 0 ${model.plot.viewWidth} ${model.plot.viewHeight}`"
        preserveAspectRatio="xMidYMid meet"
        role="img"
        :aria-label="t('dashboard.usageTrend')"
        @mousemove="onPointerMove"
        @mouseleave="onPointerLeave"
      >
        <defs>
          <linearGradient id="usage-trend-area" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="var(--em-accent)" stop-opacity="0.35" />
            <stop offset="100%" stop-color="var(--em-accent)" stop-opacity="0.02" />
          </linearGradient>
          <linearGradient id="usage-trend-line" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stop-color="#a78bfa" />
            <stop offset="100%" stop-color="var(--em-accent)" />
          </linearGradient>
          <filter id="usage-trend-glow" x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur stdDeviation="1.6" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <rect
          class="em-line-chart__plot-bg"
          :x="model.plot.left"
          :y="model.plot.top"
          :width="model.plot.width"
          :height="model.plot.height"
          rx="8"
        />

        <line
          v-for="tick in model.yTicks"
          :key="`grid-${tick.value}`"
          class="em-line-chart__grid"
          :x1="model.plot.left"
          :x2="model.plot.left + model.plot.width"
          :y1="tick.y"
          :y2="tick.y"
        />

        <text
          v-for="tick in model.yTicks"
          :key="`ylabel-${tick.value}`"
          class="em-line-chart__ylabel"
          :x="model.plot.left - 8"
          :y="tick.y + 3"
        >
          {{ tick.value }}
        </text>

        <path class="em-line-chart__area" :d="model.areaPath" fill="url(#usage-trend-area)" />
        <path
          class="em-line-chart__line"
          :d="model.linePath"
          fill="none"
          stroke="url(#usage-trend-line)"
          filter="url(#usage-trend-glow)"
        />

        <g v-for="point in model.points" :key="`point-${point.index}`">
          <circle
            class="em-line-chart__hit"
            :cx="point.x"
            :cy="point.y"
            r="12"
            @mouseenter="hoverIndex = point.index"
          />
          <circle
            class="em-line-chart__dot"
            :class="{ 'em-line-chart__dot--active': hoverIndex === point.index }"
            :cx="point.x"
            :cy="point.y"
            :r="hoverIndex === point.index ? 5 : 3.5"
          />
        </g>

        <g v-for="point in model.points" :key="`xlabel-${point.index}`">
          <text class="em-line-chart__xlabel" :x="point.x" :y="model.plot.baseline + 14">
            {{ point.label.weekday }}
          </text>
          <text class="em-line-chart__xsub" :x="point.x" :y="model.plot.baseline + 24">
            {{ point.label.day }}
          </text>
        </g>

        <g v-if="activePoint" class="em-line-chart__tooltip">
          <line
            class="em-line-chart__crosshair"
            :x1="activePoint.x"
            :x2="activePoint.x"
            :y1="model.plot.top"
            :y2="model.plot.baseline"
          />
          <rect
            class="em-line-chart__tooltip-box"
            :x="Math.min(Math.max(activePoint.x - 42, model.plot.left), model.plot.left + model.plot.width - 84)"
            :y="Math.max(activePoint.y - 44, model.plot.top)"
            width="84"
            height="34"
            rx="8"
          />
          <text
            class="em-line-chart__tooltip-value"
            :x="Math.min(Math.max(activePoint.x, model.plot.left + 42), model.plot.left + model.plot.width - 42)"
            :y="Math.max(activePoint.y - 26, model.plot.top + 14)"
          >
            {{ activePoint.value }} {{ t('dashboard.taskRuns') }}
          </text>
          <text
            class="em-line-chart__tooltip-day"
            :x="Math.min(Math.max(activePoint.x, model.plot.left + 42), model.plot.left + model.plot.width - 42)"
            :y="Math.max(activePoint.y - 14, model.plot.top + 26)"
          >
            {{ activePoint.label.compact }}
          </text>
        </g>
      </svg>
    </div>
  </article>
</template>
