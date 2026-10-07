const PLOT = {
  left: 44,
  right: 16,
  top: 16,
  bottom: 36,
  width: 560,
  height: 240,
};

PLOT.viewWidth = PLOT.left + PLOT.width + PLOT.right;
PLOT.viewHeight = PLOT.top + PLOT.height + PLOT.bottom;
PLOT.baseline = PLOT.top + PLOT.height;

function niceCeil(value) {
  if (value <= 0) {
    return 4;
  }
  const magnitude = 10 ** Math.floor(Math.log10(value));
  const normalized = value / magnitude;
  if (normalized <= 1) {
    return magnitude;
  }
  if (normalized <= 2) {
    return 2 * magnitude;
  }
  if (normalized <= 5) {
    return 5 * magnitude;
  }
  return 10 * magnitude;
}

function buildYAxisScale(maxValue) {
  const max = niceCeil(maxValue);
  const step = max <= 5 ? 1 : max / 4;
  const ticks = [];
  for (let value = 0; value <= max; value += step) {
    const ratio = max === 0 ? 0 : value / max;
    const y = PLOT.baseline - ratio * PLOT.height;
    ticks.push({ value: Math.round(value), y });
  }
  return { max, ticks };
}

const TREND_RANGES = {
  day: 24,
  week: 7,
  month: 30,
};

function resolveTrendRange(range) {
  if (range === 'day' || range === 'week' || range === 'month') {
    return range;
  }
  if (typeof range === 'number') {
    if (range <= 1) return 'day';
    if (range <= 7) return 'week';
    return 'month';
  }
  return 'week';
}

function buildTrendBuckets(range, now = new Date()) {
  if (range === 'day') {
    const start = new Date(now);
    start.setHours(0, 0, 0, 0);
    return Array.from({ length: TREND_RANGES.day }, (_, hour) => {
      const date = new Date(start);
      date.setHours(hour, 0, 0, 0);
      return date;
    });
  }

  const days = TREND_RANGES[range];
  const dates = [];
  for (let offset = days - 1; offset >= 0; offset -= 1) {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - offset);
    dates.push(date);
  }
  return dates;
}

function bucketStart(date, range) {
  const next = new Date(date);
  if (range === 'day') {
    next.setMinutes(0, 0, 0);
    return next;
  }
  next.setHours(0, 0, 0, 0);
  return next;
}

function estimatedCounts(range, taskCount) {
  if (range === 'day') {
    return Array.from({ length: TREND_RANGES.day }, (_, index) => (index % 6) + 1);
  }
  if (range === 'month') {
    return Array.from({ length: TREND_RANGES.month }, (_, index) => (index % 7) + 1);
  }
  return [1, 2, 1, 3, 2, 4, Math.max(taskCount, 2)];
}

export function buildTrendSeries(taskItems, range = 'week') {
  const resolved = resolveTrendRange(range);
  const dates = buildTrendBuckets(resolved);
  const counts = Array.from({ length: dates.length }, () => 0);

  for (const task of taskItems) {
    const created = Date.parse(task?.createdAt ?? '');
    if (!Number.isFinite(created)) {
      continue;
    }
    const stamp = bucketStart(created, resolved).getTime();
    const index = dates.findIndex((date) => date.getTime() === stamp);
    if (index >= 0) {
      counts[index] += 1;
    }
  }

  const hasRealData = counts.some((count) => count > 0);
  if (!hasRealData) {
    return {
      counts: estimatedCounts(resolved, taskItems.length),
      dates,
      isEstimated: true,
      range: resolved,
    };
  }

  return { counts, dates, isEstimated: false, range: resolved };
}

function formatBucketLabel(date, locale, range) {
  if (range === 'day') {
    const hour = date.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' });
    return { weekday: hour, day: '', compact: hour };
  }
  const weekday = date.toLocaleDateString(locale, { weekday: 'short' });
  const day = date.toLocaleDateString(locale, { day: 'numeric', month: 'short' });
  return { weekday, day, compact: `${weekday} ${day}` };
}

function labelStep(range) {
  if (range === 'day') return 4;
  if (range === 'month') return 5;
  return 1;
}

function buildSmoothLinePath(points) {
  if (!points.length) {
    return '';
  }
  if (points.length === 1) {
    return `M ${points[0].x},${points[0].y}`;
  }

  let path = `M ${points[0].x},${points[0].y}`;
  for (let index = 0; index < points.length - 1; index += 1) {
    const current = points[index];
    const next = points[index + 1];
    const controlX = (current.x + next.x) / 2;
    path += ` C ${controlX},${current.y} ${controlX},${next.y} ${next.x},${next.y}`;
  }
  return path;
}

function buildSmoothAreaPath(points, baseline) {
  if (!points.length) {
    return '';
  }
  const line = buildSmoothLinePath(points);
  const last = points[points.length - 1];
  const first = points[0];
  return `${line} L ${last.x},${baseline} L ${first.x},${baseline} Z`;
}

export function buildLineChartModel(taskItems, locale = 'en', range = 'week') {
  const series = buildTrendSeries(taskItems, range);
  const { counts, dates, isEstimated } = series;
  const rawMax = Math.max(...counts, 1);
  const scale = buildYAxisScale(rawMax);
  const step = counts.length > 1 ? PLOT.width / (counts.length - 1) : 0;
  const every = labelStep(series.range);

  const points = counts.map((value, index) => {
    const x = PLOT.left + index * step;
    const ratio = scale.max === 0 ? 0 : value / scale.max;
    const y = PLOT.baseline - ratio * PLOT.height;
    const date = dates[index] ?? new Date();
    return {
      x,
      y,
      value,
      index,
      showLabel: index % every === 0 || index === counts.length - 1,
      label: formatBucketLabel(date, locale, series.range),
    };
  });

  const total = counts.reduce((sum, count) => sum + count, 0);
  const peak = Math.max(...counts, 0);
  const average = counts.length ? total / counts.length : 0;

  return {
    points,
    counts,
    range: series.range,
    isEstimated,
    total,
    peak,
    average,
    yTicks: scale.ticks,
    yMax: scale.max,
    linePath: buildSmoothLinePath(points),
    areaPath: buildSmoothAreaPath(points, PLOT.baseline),
    plot: { ...PLOT },
  };
}

export function buildDonutGradient(slices) {
  if (!slices.length) {
    return 'conic-gradient(from -90deg, var(--md-surface-container-highest) 0 100%)';
  }

  let cursor = 0;
  const stops = [];
  for (const slice of slices) {
    const start = cursor;
    cursor += slice.pct;
    stops.push(`${slice.color} ${start}% ${cursor}%`);
  }
  if (cursor < 100) {
    stops.push(`var(--md-surface-container-highest) ${cursor}% 100%`);
  }
  return `conic-gradient(from -90deg, ${stops.join(', ')})`;
}

export { PLOT as CHART_PLOT };
