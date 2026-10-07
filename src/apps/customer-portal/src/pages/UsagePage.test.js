import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { portalApi } from '../api/client';
import { session } from '../auth/session';
import UsagePage from './UsagePage.vue';

describe('UsagePage', () => {
  afterEach(() => {
    session.workspaceId = null;
    session.permissions = [];
    vi.restoreAllMocks();
  });

  it('shows spend details, status breakdown, and the usage chart', async () => {
    session.workspaceId = 'ws-usage';
    session.permissions = ['customer.billing:read', 'customer.tasks:read'];
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-07',
      taskCount: 4,
      computeMicroEur: 4_000_000,
    });
    vi.spyOn(portalApi, 'balance').mockResolvedValue({
      availableMicroEur: 6_000_000,
      reservedMicroEur: 1_000_000,
    });
    vi.spyOn(portalApi, 'tasks').mockResolvedValue({
      items: [
        { id: '1', taskType: 'text.direct', lifecycleStatus: 'succeeded', createdAt: new Date().toISOString() },
        { id: '2', taskType: 'text.direct', lifecycleStatus: 'running', createdAt: new Date().toISOString() },
        { id: '3', taskType: 'text.summarize', lifecycleStatus: 'queued', createdAt: new Date().toISOString() },
        { id: '4', taskType: 'text.direct', lifecycleStatus: 'cancelled', createdAt: new Date().toISOString() },
      ],
    });

    const wrapper = mount(UsagePage);
    await flushPromises();

    expect(wrapper.text()).toContain('Usage Trend');
    expect(wrapper.text()).toContain('By status');
    expect(wrapper.text()).toContain('done');
    expect(wrapper.text()).toContain('running');
    expect(wrapper.text()).toContain('queued');
    expect(wrapper.text()).toContain('cancel');
    expect(wrapper.text()).toContain('2026-07');
    expect(wrapper.text()).toContain('36%');
    expect(wrapper.find('svg.em-line-chart').exists()).toBe(true);
    expect(wrapper.findAll('.em-bar-list__fill--done, .em-bar-list__fill--running, .em-bar-list__fill--queued, .em-bar-list__fill--cancel')).toHaveLength(4);
  });
});
