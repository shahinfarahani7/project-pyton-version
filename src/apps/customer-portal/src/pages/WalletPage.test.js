import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { portalApi } from '../api/client';
import { session } from '../auth/session';
import AccountPage from './AccountPage.vue';
import WalletPage from './WalletPage.vue';

describe('wallet and account pages', () => {
  afterEach(() => {
    session.authenticated = false;
    session.workspaceId = null;
    session.sessionPublicId = null;
    session.permissions = [];
    vi.restoreAllMocks();
  });

  it('shows available, reserved, and spent balances', async () => {
    session.workspaceId = 'ws-wallet';
    session.permissions = ['customer.billing:read'];
    vi.spyOn(portalApi, 'wallets').mockRejectedValue(new Error('missing'));
    vi.spyOn(portalApi, 'balance').mockResolvedValue({
      availableMicroEur: 8_000_000,
      reservedMicroEur: 1_000_000,
    });
    vi.spyOn(portalApi, 'usage').mockResolvedValue({
      period: '2026-07',
      taskCount: 3,
      computeMicroEur: 2_000_000,
    });

    const wrapper = mount(WalletPage);
    await flushPromises();

    expect(wrapper.text()).toContain('Available credit');
    expect(wrapper.text()).toContain('Reserved');
    expect(wrapper.text()).toContain('Compute spend');
    expect(wrapper.text()).toContain('€8.00');
    expect(wrapper.text()).toContain('€1.00');
    expect(wrapper.text()).toContain('€2.00');
    expect(wrapper.text()).toContain('Primary');
  });

  it('adds a named wallet with a whole-euro amount', async () => {
    session.workspaceId = 'ws-wallet';
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

    const wrapper = mount(WalletPage);
    await flushPromises();
    await wrapper.get('input[type="text"]').setValue('Travel');
    await wrapper.get('input[type="number"]').setValue(5);
    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(portalApi.addWallet).toHaveBeenCalledWith('ws-wallet', {
      name: 'Travel',
      amountMicroEur: 5_000_000,
    });
    expect(wrapper.text()).toContain('Travel');
    expect(wrapper.text()).toContain('€5.00');
    expect(wrapper.text()).toContain('€13.00');
  });

  it('shows the signed-in name and email on the account page', async () => {
    session.authenticated = true;
    session.sessionPublicId = 'ses_portal';
    session.workspaceId = 'ws-account';
    session.permissions = ['customer.tasks:read'];
    vi.spyOn(portalApi, 'currentPrincipal').mockResolvedValue({
      displayName: 'Dev User',
      email: 'dev-user@edgemint.local',
    });

    const wrapper = mount(AccountPage);
    await flushPromises();

    expect(wrapper.text()).toContain('Dev User');
    expect(wrapper.text()).toContain('dev-user@edgemint.local');
    expect(wrapper.text()).toContain('ses_portal');
    expect(wrapper.text()).toContain('customer.tasks:read');
  });
});
