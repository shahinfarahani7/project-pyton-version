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
import SettingsPage from './pages/SettingsPage.vue';
import TasksPage from './pages/TasksPage.vue';
import TeamPage from './pages/TeamPage.vue';
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
        path: '/',
        component: AppShell,
        children: [
          { path: 'login', component: LoginPage },
          { path: '', component: DashboardPage, meta: { requiresAuth: true } },
          { path: 'tasks', component: TasksPage, meta: { requiresAuth: true } },
          { path: 'files', component: FilesPage, meta: { requiresAuth: true } },
          { path: 'webhooks', component: WebhooksPage, meta: { requiresAuth: true } },
          { path: 'api-keys', component: ApiKeysPage, meta: { requiresAuth: true } },
          { path: 'billing', component: BillingPage, meta: { requiresAuth: true } },
          { path: 'disputes', component: DisputesPage, meta: { requiresAuth: true } },
          { path: 'team', component: TeamPage, meta: { requiresAuth: true } },
          { path: 'settings', component: SettingsPage, meta: { requiresAuth: true } },
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
      return { path: '/login' };
    }
    if (to.path === '/login' && session.authenticated) {
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
              headers: { 'Content-Type': 'application/json', 'X-EdgeMint-CSRF-Token': 'csrf-test' },
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
    await wrapper.get('[class*="secondary-button"]').trigger('click');
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/dashboard/i);
    });
  });
});
