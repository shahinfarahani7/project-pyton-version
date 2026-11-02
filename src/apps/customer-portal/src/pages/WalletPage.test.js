import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { portalApi } from '../api/client';
import { session } from '../auth/session';
import AccountPage from './AccountPage.vue';

describe('account page', () => {
  afterEach(() => {
    session.authenticated = false;
    session.workspaceId = null;
    session.sessionPublicId = null;
    session.permissions = [];
    vi.restoreAllMocks();
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
