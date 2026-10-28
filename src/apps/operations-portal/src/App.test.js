import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import App from './App.vue';
import { session } from './auth/session';
import AppShell from './components/AppShell.vue';
import ApprovalsPage from './pages/ApprovalsPage.vue';
import DashboardPage from './pages/DashboardPage.vue';
import DisputesPage from './pages/DisputesPage.vue';
import EmergencyPage from './pages/EmergencyPage.vue';
import FraudPage from './pages/FraudPage.vue';
import IncidentsPage from './pages/IncidentsPage.vue';
import LoginPage from './pages/LoginPage.vue';
import ModelsPage from './pages/ModelsPage.vue';
import ReconciliationPage from './pages/ReconciliationPage.vue';
import TasksPage from './pages/TasksPage.vue';
import WorkersPage from './pages/WorkersPage.vue';

import { authApi, opsApi } from './api/client';

function resetSession() {
  Object.assign(session, {
    authenticated: false,
    operatorId: null,
    role: null,
    mfaVerified: false,
    permissions: [],
    error: null,
  });
}

beforeEach(() => {
  vi.spyOn(opsApi, 'devLogin').mockResolvedValue({
    operatorId: 'op_dev_1',
    role: 'operator.approver',
    mfaVerified: true,
    permissions: ['operations.approve', 'operations.mutate.low', 'operations.read'],
  });
});

function createTestRouter(initialRoute = '/login') {
  return createRouter({
    history: createMemoryHistory(initialRoute),
    routes: [
      {
        path: '/',
        component: AppShell,
        children: [
          { path: 'login', component: LoginPage },
          { path: '', component: DashboardPage, meta: { requiresAuth: true } },
          { path: 'tasks', component: TasksPage, meta: { requiresAuth: true } },
          { path: 'workers', component: WorkersPage, meta: { requiresAuth: true } },
          { path: 'models', component: ModelsPage, meta: { requiresAuth: true } },
          { path: 'fraud', component: FraudPage, meta: { requiresAuth: true } },
          { path: 'disputes', component: DisputesPage, meta: { requiresAuth: true } },
          { path: 'reconciliation', component: ReconciliationPage, meta: { requiresAuth: true } },
          { path: 'incidents', component: IncidentsPage, meta: { requiresAuth: true } },
          { path: 'approvals', component: ApprovalsPage, meta: { requiresAuth: true } },
          { path: 'emergency', component: EmergencyPage, meta: { requiresAuth: true } },
        ],
      },
    ],
  });
}

async function renderApp(route = '/login') {
  const router = createTestRouter(route);
  router.beforeEach((to) => {
    const requiresAuth = to.matched.some((record) => record.meta.requiresAuth);
    if (requiresAuth && (!session.authenticated || !session.mfaVerified)) {
      return { path: '/login' };
    }
    if (to.path === '/login' && session.authenticated && session.mfaVerified) {
      return { path: '/' };
    }
    return true;
  });
  const wrapper = mount(App, {
    global: {
      plugins: [router],
    },
    attachTo: document.body,
  });
  await router.isReady();
  return wrapper;
}

afterEach(() => {
  vi.restoreAllMocks();
  resetSession();
  document.body.innerHTML = '';
});

describe('operations-portal', () => {
  it('shows MFA-gated shell after development sign-in', async () => {
    const wrapper = await renderApp('/login');
    const buttons = wrapper.findAll('button');
    const devButton = buttons.find((button) => button.text().match(/development sign-in/i));
    expect(devButton).toBeTruthy();
    await devButton.trigger('click');
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/MFA verified/i);
    });
    expect(document.querySelector('nav[aria-label="Operations"]')).toBeTruthy();
  });

  it('stays signed out when the server rejects development sign-in', async () => {
    opsApi.devLogin.mockRejectedValue(new Error('Development sign-in disabled'));
    const wrapper = await renderApp('/login');
    const devButton = wrapper.findAll('button').find((button) => button.text().match(/development sign-in/i));
    await devButton.trigger('click');
    await vi.waitFor(() => {
      expect(document.querySelector('[role="alert"]')?.textContent.trim()).toBe('Development sign-in disabled');
    });
    expect(session.authenticated).toBe(false);
    expect(document.querySelector('nav[aria-label="Operations"]')).toBeNull();
  });

  it('renders separate admin and customer sign-in without provider tokens', async () => {
    const wrapper = await renderApp('/login');
    expect(document.body.textContent).toMatch(/admin sign-in/i);
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
    await wrapper.findAll('[role="tab"]').find((tab) => tab.text() === 'Customer').trigger('click');
    expect(document.body.textContent).toMatch(/customer sign-in/i);
    expect(document.querySelector('a.primary-link')?.getAttribute('href')).toMatch(/:5173\/login$/);
  });

  it('admin password sign-in authenticates then enters the admin session', async () => {
    const loginWithPassword = vi.spyOn(authApi, 'loginWithPassword').mockResolvedValue({});
    vi.spyOn(opsApi, 'portalLogin').mockResolvedValue({
      operatorId: 'boss@example.com',
      role: 'operator.approver',
      mfaVerified: true,
      permissions: ['operations.read'],
    });
    const wrapper = await renderApp('/login');
    await wrapper.find('input[type="email"]').setValue('boss@example.com');
    await wrapper.find('input[type="password"]').setValue('secret-pass');
    await wrapper.find('form').trigger('submit');
    await vi.waitFor(() => {
      expect(document.querySelector('nav[aria-label="Operations"]')).toBeTruthy();
    });
    expect(loginWithPassword).toHaveBeenCalledWith({ email: 'boss@example.com', password: 'secret-pass' });
  });

  it('non-admin account stays on the login page with an error', async () => {
    vi.spyOn(authApi, 'loginWithPassword').mockResolvedValue({});
    vi.spyOn(opsApi, 'portalLogin').mockRejectedValue(new Error('portal account is not an operations admin'));
    const wrapper = await renderApp('/login');
    await wrapper.find('input[type="email"]').setValue('customer@example.com');
    await wrapper.find('input[type="password"]').setValue('secret-pass');
    await wrapper.find('form').trigger('submit');
    await vi.waitFor(() => {
      expect(document.querySelector('[role="alert"]')?.textContent).toMatch(/not an operations admin/);
    });
    expect(session.authenticated).toBe(false);
  });

  it('admin email-code sign-in requests and verifies the code', async () => {
    vi.spyOn(authApi, 'requestEmailOtp').mockResolvedValue({ challengeId: 'chl_1', devCode: '123456' });
    const verify = vi.spyOn(authApi, 'verifyEmailOtp').mockResolvedValue({});
    vi.spyOn(opsApi, 'portalLogin').mockResolvedValue({
      operatorId: 'boss@example.com',
      role: 'operator.approver',
      mfaVerified: true,
      permissions: ['operations.read'],
    });
    const wrapper = await renderApp('/login');
    await wrapper.findAll('.method-switch button').find((b) => b.text() === 'Email code').trigger('click');
    await wrapper.find('input[type="email"]').setValue('boss@example.com');
    await wrapper.find('form').trigger('submit');
    await vi.waitFor(() => expect(wrapper.find('input[inputmode="numeric"]').exists()).toBe(true));
    await wrapper.find('input[inputmode="numeric"]').setValue('123456');
    await wrapper.find('form').trigger('submit');
    await vi.waitFor(() => {
      expect(document.querySelector('nav[aria-label="Operations"]')).toBeTruthy();
    });
    expect(verify).toHaveBeenCalledWith({ email: 'boss@example.com', challengeId: 'chl_1', code: '123456' });
  });

  it('hides break-glass navigation without permission', async () => {
    const wrapper = await renderApp('/login');
    const buttons = wrapper.findAll('button');
    const devButton = buttons.find((button) => button.text().match(/development sign-in/i));
    await devButton.trigger('click');
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/MFA verified/i);
    });
    expect(document.body.textContent?.toLowerCase()).not.toMatch(/\bemergency\b/);
  });
});
