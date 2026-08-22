import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

import App from './App.vue';
import { session } from './auth/session';
import AppShell from './components/AppShell.vue';
import ApiKeysPage from './pages/ApiKeysPage.vue';
import BillingPage from './pages/BillingPage.vue';
import DashboardPage from './pages/DashboardPage.vue';
import DisputesPage from './pages/DisputesPage.vue';
import FilesPage from './pages/FilesPage.vue';
import LoginPage from './pages/LoginPage.vue';
import MorePage from './pages/MorePage.vue';
import SettingsPage from './pages/SettingsPage.vue';
import TaskDetailPage from './pages/TaskDetailPage.vue';
import TasksPage from './pages/TasksPage.vue';
import TeamPage from './pages/TeamPage.vue';
import UsagePage from './pages/UsagePage.vue';
import WebhooksPage from './pages/WebhooksPage.vue';

function resetSession() {
  Object.assign(session, {
    authenticated: false,
    sessionPublicId: null,
    workspaceId: null,
    authorizationGeneration: null,
    workspaces: [],
    permissions: [],
  });
}

function createTestRouter(initialRoute = '/login') {
  return createRouter({
    history: createMemoryHistory(initialRoute),
    routes: [
      {
        path: '/login',
        name: 'login',
        component: LoginPage,
        meta: { guest: true },
      },
      {
        path: '/',
        component: AppShell,
        meta: { requiresAuth: true },
        children: [
          { path: '', name: 'dashboard', component: DashboardPage },
          { path: 'tasks', name: 'tasks', component: TasksPage },
          { path: 'tasks/:id', name: 'task-detail', component: TaskDetailPage },
          { path: 'usage', name: 'usage', component: UsagePage },
          { path: 'billing', name: 'billing', component: BillingPage },
          { path: 'more', name: 'more', component: MorePage },
          { path: 'files', name: 'files', component: FilesPage },
          { path: 'webhooks', name: 'webhooks', component: WebhooksPage },
          { path: 'api-keys', name: 'api-keys', component: ApiKeysPage },
          { path: 'disputes', name: 'disputes', component: DisputesPage },
          { path: 'team', name: 'team', component: TeamPage },
          { path: 'settings', name: 'settings', component: SettingsPage },
        ],
      },
    ],
  });
}

async function renderApp(initialRoute = '/login') {
  const router = createTestRouter(initialRoute);
  router.beforeEach((to) => {
    const requiresAuth = to.matched.some((record) => record.meta.requiresAuth);
    if (requiresAuth && !session.authenticated) {
      return { name: 'login' };
    }
    if (to.meta.guest && session.authenticated) {
      return { name: 'dashboard' };
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
  return { wrapper, router };
}

afterEach(() => {
  resetSession();
  vi.unstubAllGlobals();
  document.body.innerHTML = '';
});

describe('customer-portal shell', () => {
  it('renders login journey without provider tokens in the DOM', async () => {
    await renderApp('/login');
    expect(document.body.textContent).toMatch(/sign in/i);
    expect(document.body.textContent).toContain('opaque BFF cookie');
    expect(document.body.textContent?.toLowerCase()).not.toContain('access_token');
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
  });

  it('redirects authenticated users away from login', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input) => {
        const url = String(input);
        if (url.endsWith('/auth/sessions') && !url.includes('logout')) {
          return new Response(
            JSON.stringify({
              sessionPublicId: 'ses_test',
              workspaceId: '00000000-0000-0000-0000-00000000000b',
              authorizationGeneration: 1,
              expiresAt: '2026-12-31T00:00:00Z',
            }),
            {
              status: 200,
              headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': 'csrf-test' },
            },
          );
        }
        return new Response(JSON.stringify({ items: [], page: { hasMore: false, nextCursor: '' } }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }),
    );

    const { wrapper } = await renderApp('/login');
    await wrapper.get('[data-testid="dev-sign-in"]').trigger('click');
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/dashboard/i);
    });
  });
});
