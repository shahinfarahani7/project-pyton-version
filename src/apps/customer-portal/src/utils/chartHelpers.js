const PLOT = {
  left: 44,
  right: 12,
  top: 20,
  bottom: 28,
  width: 300,
  height: 160,
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

export function buildTrendSeries(taskItems, days = 7) {
  const counts = Array.from({ length: days }, () => 0);
  const dates = [];
  const now = new Date();

  for (let offset = days - 1; offset >= 0; offset -= 1) {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - offset);
    dates.push(date);
  }

  for (const task of taskItems) {
    const created = Date.parse(task?.createdAt ?? '');
    if (!Number.isFinite(created)) {
      continue;
    }
    const taskDay = new Date(created);
    taskDay.setHours(0, 0, 0, 0);
    const index = dates.findIndex((date) => date.getTime() === taskDay.getTime());
    if (index >= 0) {
      counts[index] += 1;
    }
  }

  const hasRealData = counts.some((count) => count > 0);
  if (!hasRealData) {
    return {
      counts: [1, 2, 1, 3, 2, 4, Math.max(taskItems.length, 2)],
      dates,
      isEstimated: true,
    };
  }

  return { counts, dates, isEstimated: false };
}

function formatDayLabel(date, locale) {
  const weekday = date.toLocaleDateString(locale, { weekday: 'short' });
  const day = date.toLocaleDateString(locale, { day: 'numeric', month: 'short' });
  return { weekday, day, compact: `${weekday} ${day}` };
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

export function buildLineChartModel(taskItems, locale = 'en') {
  const series = buildTrendSeries(taskItems);
  const { counts, dates, isEstimated } = series;
  const rawMax = Math.max(...counts, 1);
  const scale = buildYAxisScale(rawMax);
  const step = counts.length > 1 ? PLOT.width / (counts.length - 1) : 0;

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
      label: formatDayLabel(date, locale),
    };
  });

  const total = counts.reduce((sum, count) => sum + count, 0);
  const peak = Math.max(...counts, 0);
  const average = counts.length ? total / counts.length : 0;

  return {
    points,
    counts,
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
