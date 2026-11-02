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
    vi.spyOn(portalApi, 'wallets').mockRejectedValue(new Error('missing'));
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
    expect(wrapper.text()).toContain('Primary');
  });

  it('adds a named wallet with a whole-euro amount', async () => {
    session.workspaceId = 'ws-billing';
    session.permissions = ['customer.billing:read'];
    const items = [
      {
        id: 'wal_primary',
        name: 'Primary',
        availableMicroEur: 8_000_000,
        reservedMicroEur: 0,
        builtin: true,
      },
    ];
    vi.spyOn(portalApi, 'wallets').mockImplementation(async () => ({ items }));
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-07',
      taskCount: 1,
      computeMicroEur: 0,
    });
    vi.spyOn(portalApi, 'invoices').mockResolvedValue({ items: [] });
    vi.spyOn(portalApi, 'addWallet').mockImplementation(async (_workspaceId, body) => {
      const created = {
        id: 'wal_new',
        name: body.name,
        availableMicroEur: body.amountMicroEur,
        reservedMicroEur: 0,
        builtin: false,
      };
      items.push(created);
      return created;
    });

    const wrapper = mount(BillingPage);
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await wrapper.get('input[type="text"]').setValue('Travel');
    await wrapper.get('input[type="number"]').setValue(5);
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(portalApi.addWallet).toHaveBeenCalledWith('ws-billing', {
      name: 'Travel',
      amountMicroEur: 5_000_000,
    });
    expect(wrapper.text()).toContain('Travel');
    expect(wrapper.text()).toContain('€5.00');
    expect(wrapper.text()).toContain('€13.00');
  });
});
