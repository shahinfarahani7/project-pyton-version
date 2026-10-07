import { describe, expect, it } from 'vitest';

import { buildDonutGradient, buildLineChartModel, buildTrendSeries } from './chartHelpers.js';

describe('chartHelpers', () => {
  it('builds a chart model with smooth paths and axis ticks', () => {
    const tasks = [
      { createdAt: new Date().toISOString() },
      { createdAt: new Date().toISOString() },
      { createdAt: new Date(Date.now() - 86_400_000).toISOString() },
    ];
    const model = buildLineChartModel(tasks, 'en');
    expect(model.linePath).toMatch(/^M /);
    expect(model.areaPath).toContain('Z');
    expect(model.points).toHaveLength(7);
    expect(model.yTicks.length).toBeGreaterThan(1);
    expect(model.total).toBeGreaterThan(0);
  });

  it('builds conic gradient stops for donut slices', () => {
    const gradient = buildDonutGradient([
      { label: 'text', pct: 60, color: '#7c4dff' },
      { label: 'ocr', pct: 40, color: '#34d399' },
    ]);
    expect(gradient).toContain('conic-gradient');
    expect(gradient).toContain('#7c4dff 0% 60%');
    expect(gradient).toContain('#34d399 60% 100%');
  });

  it('falls back to demo trend when no dated tasks exist', () => {
    const series = buildTrendSeries([]);
    expect(series.counts).toEqual([1, 2, 1, 3, 2, 4, 2]);
    expect(series.isEstimated).toBe(true);
    expect(series.dates).toHaveLength(7);
  });

  it('builds hourly day buckets and daily month buckets', () => {
    const now = new Date();
    const tasks = [{ createdAt: now.toISOString() }];
    const day = buildLineChartModel(tasks, 'en', 'day');
    const month = buildLineChartModel(tasks, 'en', 'month');

    expect(day.points).toHaveLength(24);
    expect(day.range).toBe('day');
    expect(day.points[now.getHours()].value).toBe(1);
    expect(month.points).toHaveLength(30);
    expect(month.range).toBe('month');
    expect(month.points.at(-1).value).toBe(1);
    expect(month.points.filter((point) => point.showLabel).length).toBeLessThan(30);
  });
});
