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
      availableFibonAtomic: 1_284_000,
      reservedFibonAtomic: 48_000,
    });
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-07',
      computeFibonAtomic: 186_000,
    });
    vi.spyOn(portalApi, 'invoices').mockResolvedValue({
      items: [
        { id: 'inv_dev_open_001', status: 'open', amountFibonAtomic: 420_000 },
        { id: 'inv_dev_paid_002', status: 'paid', amountFibonAtomic: 862_000 },
      ],
    });

    const wrapper = mount(BillingPage);
    await flushPromises();

    expect(wrapper.text()).toContain('Available credit');
    expect(wrapper.text()).toContain('Credit at work');
    expect(wrapper.text()).toContain('128.4 FIBON');
    expect(wrapper.text()).toContain('4.8 FIBON');
    expect(wrapper.text()).toContain('18.6 FIBON');
    expect(wrapper.text()).toContain('FIBON');
    expect(wrapper.text()).toContain('2026-07');
    expect(wrapper.text()).toContain('Open invoices');
    expect(wrapper.text()).toContain('Held on open tasks');
    expect(wrapper.text()).not.toContain('Amount due');
    expect(wrapper.text()).toContain('42 FIBON');
    expect(wrapper.text()).toContain('86.2 FIBON');
    expect(wrapper.text()).not.toContain('€');
    expect(wrapper.text()).not.toContain('EUR');
    expect(wrapper.text()).toContain('inv_dev_open_001');
    expect(wrapper.text()).toContain('Open');
    expect(wrapper.text()).toContain('Paid');
    expect(wrapper.text()).toContain('2 records');
    expect(wrapper.text()).not.toContain('Enterprise');
    expect(wrapper.text()).not.toContain('October 2026');
    expect(wrapper.get('table').text()).toContain('—');
    expect(wrapper.text()).toContain('Primary');
  });

  it('adds a named wallet with a whole FIBON amount', async () => {
    session.workspaceId = 'ws-billing';
    session.permissions = ['customer.billing:read'];
    const items = [
      {
        id: 'wal_primary',
        name: 'Primary',
        availableFibonAtomic: 8_000_000,
        reservedFibonAtomic: 0,
        builtin: true,
      },
    ];
    vi.spyOn(portalApi, 'wallets').mockImplementation(async () => ({ items }));
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-07',
      taskCount: 1,
      computeFibonAtomic: 0,
    });
    vi.spyOn(portalApi, 'invoices').mockResolvedValue({ items: [] });
    vi.spyOn(portalApi, 'addWallet').mockImplementation(async (_workspaceId, body) => {
      const created = {
        id: 'wal_new',
        name: body.name,
        availableFibonAtomic: body.amountFibonAtomic,
        reservedFibonAtomic: 0,
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
      amountFibonAtomic: 50_000,
    });
    expect(wrapper.text()).toContain('Travel');
    expect(wrapper.text()).toContain('5 FIBON');
    expect(wrapper.text()).toContain('805 FIBON');
  });

  it('shows reserved fibon and the open invoice from settlement', async () => {
    session.workspaceId = 'ws-billing';
    session.permissions = ['customer.billing:read'];
    vi.spyOn(portalApi, 'wallets').mockResolvedValue({
      items: [
        {
          id: 'wal_primary',
          name: 'Primary',
          availableFibonAtomic: 10_000_000,
          reservedFibonAtomic: 400_000,
          builtin: true,
        },
      ],
    });
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-11',
      taskCount: 2,
      computeFibonAtomic: 400_000,
    });
    vi.spyOn(portalApi, 'invoices').mockResolvedValue({
      items: [
        {
          id: 'inv_open',
          status: 'open',
          amountFibonAtomic: 400_000,
          period: '2026-11',
          dueDate: '2026-11-14',
        },
        { id: 'inv_paid', status: 'paid', amountFibonAtomic: 400_000, period: '2026-11' },
        { id: 'inv_void', status: 'void', amountFibonAtomic: 400_000, period: '2026-11' },
      ],
    });

    const wrapper = mount(BillingPage);
    await flushPromises();

    expect(wrapper.text()).toContain('1000 FIBON');
    expect(wrapper.text()).toContain('40 FIBON');
    expect(wrapper.text()).toContain('FIBON');
    expect(wrapper.text()).toContain('2026-11');
    expect(wrapper.text()).toContain('Open');
    expect(wrapper.text()).toContain('Paid');
    expect(wrapper.text()).toContain('Void');
    expect(wrapper.text()).toContain('inv_open');
    expect(wrapper.text()).not.toContain('€');
  });
});
