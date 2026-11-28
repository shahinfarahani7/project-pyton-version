import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import App from './App.vue';
import { session } from './auth/session';
import AppShell from './components/AppShell.vue';
import AdminsPage from './pages/AdminsPage.vue';
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

import { opsApi } from './api/client';

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

function createTestRouter() {
  return createRouter({
    history: createMemoryHistory(),
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
          { path: 'admins', component: AdminsPage, meta: { requiresAuth: true } },
          { path: 'emergency', component: EmergencyPage, meta: { requiresAuth: true } },
        ],
      },
    ],
  });
}

async function renderApp(route = '/login') {
  const router = createTestRouter();
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
  await router.push(route);
  await router.isReady();
  const wrapper = mount(App, {
    global: {
      plugins: [router],
    },
    attachTo: document.body,
  });
  await wrapper.vm.$nextTick();
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

  it('points admins to the single portal sign-in without audience tabs', async () => {
    await renderApp('/login');
    expect(document.body.textContent).toMatch(/admin console/i);
    expect(document.body.textContent).toMatch(/sign in once on the portal/i);
    expect(document.querySelector('[role="tablist"]')).toBeNull();
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
    expect(document.body.textContent).toMatch(/go to portal sign-in/i);
  });

  it('redeems an admin handoff code into an operator session', async () => {
    vi.spyOn(opsApi, 'handoffLogin').mockResolvedValue({
      operatorId: 'boss@example.com',
      role: 'operator.approver',
      mfaVerified: true,
      permissions: ['operations.read'],
    });
    await renderApp('/login?handoff=handoff-code-1');
    await vi.waitFor(() => {
      expect(document.querySelector('nav[aria-label="Operations"]')).toBeTruthy();
    });
    expect(opsApi.handoffLogin).toHaveBeenCalledWith({ handoffCode: 'handoff-code-1' });
    expect(session.operatorId).toBe('boss@example.com');
  });

  it('shows an error when the admin handoff is rejected', async () => {
    vi.spyOn(opsApi, 'handoffLogin').mockRejectedValue(new Error('Admin handoff code is invalid or expired'));
    await renderApp('/login?handoff=bad-code');
    await vi.waitFor(() => {
      expect(document.querySelector('[role="alert"]')?.textContent).toMatch(/invalid or expired/i);
    });
    expect(session.authenticated).toBe(false);
  });

  it('sign out returns to the login page', async () => {
    vi.spyOn(opsApi, 'logout').mockResolvedValue({ status: 'signed_out' });
    const wrapper = await renderApp('/login');
    await wrapper.findAll('button').find((b) => b.text().match(/development sign-in/i)).trigger('click');
    await vi.waitFor(() => expect(document.querySelector('nav[aria-label="Operations"]')).toBeTruthy());
    await wrapper.vm.$router.push('/workers');
    await wrapper.findAll('button').find((b) => b.text() === 'Sign out').trigger('click');
    await vi.waitFor(() => expect(wrapper.vm.$router.currentRoute.value.path).toBe('/login'));
    expect(session.authenticated).toBe(false);
    expect(document.body.textContent).toMatch(/admin console/i);
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
