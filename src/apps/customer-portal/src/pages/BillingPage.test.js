import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { portalApi } from '../api/client';
import { session } from '../auth/session';
import BillingPage from './BillingPage.vue';

describe('billing page', () => {
  afterEach(() => {
    session.authenticated = false;
    session.workspaceId = null;
    session.permissions = [];
    vi.restoreAllMocks();
  });

  it('shows credit cards and invoice rows from API money', async () => {
    session.workspaceId = 'ws-billing';
    session.permissions = ['customer.billing:read'];
    vi.spyOn(portalApi, 'balance').mockResolvedValue({
      availableMicroEur: 128_400_000,
      reservedMicroEur: 4_800_000,
    });
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-07',
      computeMicroEur: 18_600_000,
    });
    vi.spyOn(portalApi, 'invoices').mockResolvedValue({
      items: [
        { id: 'inv_dev_open_001', status: 'open', amountDueMicroEur: 42_000_000 },
        { id: 'inv_dev_paid_002', status: 'paid', amountDueMicroEur: 86_200_000 },
      ],
    });

    const wrapper = mount(BillingPage);
    await flushPromises();

    expect(wrapper.text()).toContain('Available credit');
    expect(wrapper.text()).toContain('Credit at work');
    expect(wrapper.text()).toContain('€128.40');
    expect(wrapper.text()).toContain('€4.80');
    expect(wrapper.text()).toContain('€18.60');
    expect(wrapper.text()).toContain('EUR');
    expect(wrapper.text()).toContain('2026-07');
    expect(wrapper.text()).toContain('Open invoices');
    expect(wrapper.text()).toContain('€42.00');
    expect(wrapper.text()).toContain('€86.20');
    expect(wrapper.text()).toContain('inv_dev_open_001');
    expect(wrapper.text()).toContain('Open');
    expect(wrapper.text()).toContain('Paid');
    expect(wrapper.text()).toContain('2 records');
    expect(wrapper.text()).not.toContain('Enterprise');
    expect(wrapper.text()).not.toContain('October 2026');
    expect(wrapper.get('table').text()).toContain('—');
  });
});
