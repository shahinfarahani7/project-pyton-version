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
          cpu: { capacityUnits: 100, usageBps: 4200 },
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
      ],
    });

    const wrapper = mount(WorkersPage);
    await flushPromises();

    const rows = wrapper.findAll('tbody tr');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Running task');
    expect(rows[0].text()).toContain('42% used');
    expect(rows[1].text()).toContain('not reported');
    expect(rows[0].text()).toContain('2.0 GB / 8.0 GB');
    expect(rows[0].text()).toContain('85% (charging)');
    expect(rows[1].text()).toContain('Idle');
    expect(rows[1].text()).toContain('—');
  });

  it('shows an error when loading fails', async () => {
    vi.spyOn(opsApi, 'workerDevices').mockRejectedValue(new Error('boom'));
    const wrapper = mount(WorkersPage);
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe('boom');
  });
});
