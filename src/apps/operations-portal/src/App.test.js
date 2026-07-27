import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

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

function resetSession() {
  Object.assign(session, {
    authenticated: false,
    operatorId: null,
    role: null,
    mfaVerified: false,
  });
}

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
  resetSession();
  document.body.innerHTML = '';
});

describe('operations-portal', () => {
  it('renders SSO login without exposing provider tokens', async () => {
    await renderApp('/login');
    expect(document.body.textContent).toMatch(/operator sign-in/i);
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
  });

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
