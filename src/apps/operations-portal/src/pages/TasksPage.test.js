import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { opsApi } from '../api/client';
import DashboardPage from './DashboardPage.vue';
import TasksPage from './TasksPage.vue';

afterEach(() => {
  vi.restoreAllMocks();
});

const monitor = {
  summary: {
    total: 3,
    byStatus: { running: 1, failed: 1, succeeded: 1 },
    queueDepth: 0,
    running: 1,
    failedDeliveries: 1,
    pinnedDeviceId: null,
  },
  items: [
    {
      id: 'tsk_a',
      taskType: 'document.ocr',
      workspaceId: 'ws-1',
      lifecycleStatus: 'running',
      executionStatus: 'running',
      tokensGivenAtomic: 0,
      inWorkerQueue: false,
      devices: [
        { deviceId: 'dev_PHONE1', state: 'running', workerId: 'wrk_1', platform: 'android', deviceTier: 'B', deviceName: 'Samsung Galaxy S24', errorCode: null, deliveredAt: '2026-10-28T10:00:00Z' },
      ],
    },
    {
      id: 'tsk_b',
      taskType: 'text.summarize',
      workspaceId: 'ws-1',
      lifecycleStatus: 'failed',
      failureReasonCode: 'OOM',
      tokensGivenAtomic: 0,
      inWorkerQueue: false,
      devices: [
        { deviceId: 'dev_PHONE2', state: 'failed', workerId: null, platform: null, deviceTier: null, errorCode: 'OOM', deliveredAt: null },
      ],
    },
    {
      id: 'tsk_c',
      taskType: 'text.direct',
      workspaceId: 'ws-1',
      lifecycleStatus: 'succeeded',
      fibonaiSettlement: 'spent',
      fibonaiWorkerRewardAtomic: 300000,
      inWorkerQueue: false,
      devices: [],
    },
  ],
};

describe('TasksPage', () => {
  it('shows which device each task went to and filters by status', async () => {
    vi.spyOn(opsApi, 'taskMonitor').mockResolvedValue(monitor);
    const wrapper = mount(TasksPage);
    await flushPromises();

    expect(wrapper.get('[data-stat="done"] strong').text()).toBe('1');
    expect(wrapper.get('[data-stat="failed"] strong').text()).toBe('1');
    expect(wrapper.get('[data-stat="uptime"] strong').text()).toBe('50%');

    const rows = wrapper.findAll('tbody tr');
    expect(rows).toHaveLength(3);
    const phone = rows[0].find('.device-list');
    expect(phone.text()).toContain('Samsung Galaxy S24');
    expect(phone.text()).not.toContain('running');
    expect(phone.find('.pill').exists()).toBe(false);
    expect(rows[1].find('.device-list').text()).toContain('dev_PHONE2');
    expect(rows[1].text()).toContain('OOM');
    expect(rows[0].get('[data-field="tokens-paid"]').text()).toBe('0 FIBON');
    expect(rows[2].get('[data-field="tokens-paid"]').text()).toBe('30 FIBON');

    await wrapper.find('select').setValue('failed');
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    expect(wrapper.find('tbody').text()).toContain('tsk_b');

    await wrapper.find('select').setValue('all');
    await wrapper.find('.filters input').setValue('PHONE1');
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    expect(wrapper.find('tbody').text()).toContain('tsk_a');
    wrapper.unmount();
  });

  it('shows an em dash uptime when no task has finished', async () => {
    vi.spyOn(opsApi, 'taskMonitor').mockResolvedValue({
      summary: {
        total: 1,
        byStatus: { running: 1 },
        queueDepth: 0,
        running: 1,
        failedDeliveries: 0,
        pinnedDeviceId: null,
      },
      items: [
        {
          id: 'tsk_run',
          taskType: 'text.direct',
          workspaceId: 'ws-1',
          lifecycleStatus: 'running',
          inWorkerQueue: false,
          devices: [],
        },
      ],
    });
    const wrapper = mount(TasksPage);
    await flushPromises();
    expect(wrapper.get('[data-stat="done"] strong').text()).toBe('0');
    expect(wrapper.get('[data-stat="failed"] strong').text()).toBe('0');
    expect(wrapper.get('[data-stat="uptime"] strong').text()).toBe('—');
    wrapper.unmount();
  });

  it('cancels an open task and hides cancel on a finished task', async () => {
    vi.spyOn(opsApi, 'taskMonitor').mockResolvedValue(monitor);
    const cancel = vi.spyOn(opsApi, 'cancelTask').mockResolvedValue({
      id: 'tsk_a',
      lifecycleStatus: 'cancelled',
    });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    const wrapper = mount(TasksPage);
    await flushPromises();

    const buttons = wrapper.findAll('tbody button');
    expect(buttons).toHaveLength(1);
    expect(buttons[0].text()).toBe('Cancel');
    await buttons[0].trigger('click');
    await flushPromises();
    expect(cancel).toHaveBeenCalledWith('tsk_a');
    wrapper.unmount();
  });

  it('shows an upstream error instead of an empty table', async () => {
    vi.spyOn(opsApi, 'taskMonitor').mockRejectedValue(new Error('Upstream service unavailable'));
    const wrapper = mount(TasksPage);
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe('Upstream service unavailable');
    wrapper.unmount();
  });
});

describe('DashboardPage', () => {
  it('raises alerts for failed deliveries and work waiting with no online worker', async () => {
    vi.spyOn(opsApi, 'overview').mockResolvedValue({
      workers: { total: 2, byPresence: { offline: 2 }, byActivity: { unknown: 2 }, lowBattery: 0, hotDevices: 0 },
      tasks: { ...monitor.summary, queueDepth: 3 },
      tasksError: null,
    });
    const wrapper = mount(DashboardPage, { global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } } });
    await flushPromises();
    const alerts = wrapper.find('[aria-label="Alerts"]').text();
    expect(alerts).toContain('1 failed task deliveries');
    expect(alerts).toContain('no worker is online');
    wrapper.unmount();
  });

  it('shows tokens sold to customers and tokens paid for completed tasks', async () => {
    vi.spyOn(opsApi, 'overview').mockResolvedValue({
      workers: { total: 0, byPresence: {}, byActivity: {}, lowBattery: 0, hotDevices: 0 },
      tasks: null,
      tasksError: null,
      tokens: { soldAtomic: 400000, issuedAtomic: 300000 },
    });
    const wrapper = mount(DashboardPage, { global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } } });
    await flushPromises();
    expect(wrapper.get('[data-stat="tokens-sold"]').text()).toContain('Sold');
    expect(wrapper.get('[data-stat="tokens-sold"]').text()).toContain('40 FIBON');
    expect(wrapper.get('[data-stat="tokens-given"]').text()).toContain('Paid for tasks');
    expect(wrapper.get('[data-stat="tokens-given"]').text()).toContain('30 FIBON');
    wrapper.unmount();
  });
});
