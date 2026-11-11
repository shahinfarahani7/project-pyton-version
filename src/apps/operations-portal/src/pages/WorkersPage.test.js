import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { opsApi } from '../api/client';
import WorkersPage from './WorkersPage.vue';

afterEach(() => {
  vi.restoreAllMocks();
});

describe('WorkersPage', () => {
  it('lists workers with cpu, ram, battery and task activity', async () => {
    vi.spyOn(opsApi, 'workerDevices').mockResolvedValue({
      items: [
        {
          id: 'dev_1',
          workerId: 'wrk_1',
          status: 'active',
          presence: 'online',
          activity: 'busy',
          platform: 'android',
          device: { name: 'Galaxy S24 Ultra', manufacturer: 'samsung', model: 'SM-S928B' },
          cpu: { capacityUnits: 100, cores: 8, usageBps: 4200 },
          ram: { totalBytes: 8 * 1024 ** 3, freeBytes: 2 * 1024 ** 3 },
          battery: { levelBps: 8500, charging: true },
          lastHeartbeatAt: '2026-10-28T10:00:00+00:00',
        },
        {
          id: 'dev_2',
          workerId: 'wrk_2',
          status: 'active',
          presence: 'online',
          activity: 'idle',
          cpu: { capacityUnits: 100, usageBps: null },
          ram: { totalBytes: null, freeBytes: null },
          battery: { levelBps: null, charging: null },
          lastHeartbeatAt: null,
        },
        {
          id: 'dev_3',
          workerId: 'wrk_3',
          status: 'active',
          presence: 'offline',
          activity: 'unknown',
          cpu: { cores: 8, usageBps: 9000 },
          ram: { totalBytes: 8 * 1024 ** 3, freeBytes: 1024 ** 3 },
          battery: { levelBps: 4000, charging: false },
          lastHeartbeatAt: '2026-10-28T09:00:00+00:00',
        },
      ],
    });

    const wrapper = mount(WorkersPage);
    await flushPromises();

    const rows = wrapper.findAll('tbody tr');
    expect(rows).toHaveLength(3);
    expect(rows[0].text()).toContain('Online');
    expect(rows[0].text()).toContain('Running task');
    expect(rows[0].find('.device-name strong').text()).toBe('Galaxy S24 Ultra');
    expect(rows[0].find('.device-name small').text()).toBe('SM-S928B · android');
    expect(rows[1].find('.device-name strong').text()).toBe('Unknown device');
    expect(rows[0].text()).toContain('8 cores · 42% used');
    expect(rows[1].text()).toContain('not reported');
    expect(rows[0].text()).toContain('2.0 GB / 8.0 GB');
    expect(rows[0].text()).toContain('85% (charging)');
    expect(rows[1].text()).toContain('Idle');
    expect(rows[1].text()).toContain('—');
    expect(rows[2].text()).toContain('Offline');
    expect(rows[2].text()).not.toContain('90%');
    expect(rows[2].text()).toContain('—');
  });

  it('lists workers who are on the published app build', async () => {
    vi.spyOn(opsApi, 'workerDevices').mockResolvedValue({
      release: { versionName: '5.0.1', versionCode: 40200 },
      items: [
        {
          id: 'dev_new',
          workerId: 'wrk_new',
          status: 'active',
          presence: 'online',
          activity: 'idle',
          appVersion: '5.0.1',
          appVersionCode: 40200,
          appUpdated: true,
          device: { name: 'Pixel 8' },
          cpu: {},
          ram: {},
          battery: {},
          lastHeartbeatAt: null,
        },
        {
          id: 'dev_old',
          workerId: 'wrk_old',
          status: 'active',
          presence: 'offline',
          activity: 'unknown',
          appVersion: '5.0.0',
          appVersionCode: 40100,
          appUpdated: false,
          device: { name: 'Old phone' },
          cpu: {},
          ram: {},
          battery: {},
          lastHeartbeatAt: null,
        },
      ],
    });
    const wrapper = mount(WorkersPage);
    await flushPromises();
    expect(wrapper.findAll('[data-table="workers"] tbody tr')).toHaveLength(2);
    expect(wrapper.text()).toContain('Published build 5.0.1 (40200)');

    await wrapper.find('select').setValue('latest');
    const rows = wrapper.findAll('[data-table="workers"] tbody tr');
    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain('Pixel 8');
    expect(rows[0].text()).toContain('5.0.1 (40200)');
    expect(wrapper.find('[data-table="workers"]').text()).not.toContain('Old phone');
    wrapper.unmount();
  });

  it('shows an error when loading fails', async () => {
    vi.spyOn(opsApi, 'workerDevices').mockRejectedValue(new Error('boom'));
    const wrapper = mount(WorkersPage);
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe('boom');
  });
});
