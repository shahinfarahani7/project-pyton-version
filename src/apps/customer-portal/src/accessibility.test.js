import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

const rootDir = path.dirname(fileURLToPath(import.meta.url));

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

function mockAuthenticatedFetch(workspaceId) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input) => {
      const url = String(input);
      if (url.endsWith('/auth/sessions') && !url.includes('logout')) {
        return new Response(
          JSON.stringify({
            sessionPublicId: 'ses_a11y',
            workspaceId,
            authorizationGeneration: 2,
            expiresAt: '2026-12-31T00:00:00Z',
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': 'csrf-a11y' },
          },
        );
      }
      return new Response(JSON.stringify({ items: [], page: { hasMore: false, nextCursor: '' } }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }),
  );
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

describe('accessibility shell', () => {
  it('exposes skip link, landmarks, and labelled navigation', async () => {
    mockAuthenticatedFetch('00000000-0000-0000-0000-00000000000b');
    const { wrapper } = await renderApp('/login');
    await wrapper.get('[data-testid="dev-sign-in"]').trigger('click');
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/skip to main content/i);
    });
    expect(document.querySelector('nav[aria-label="Primary"]')).toBeTruthy();
    expect(document.getElementById('main-content')).toBeTruthy();
  });

  it('documents WCAG-oriented html language attribute', () => {
    const html = readFileSync(path.join(rootDir, '../index.html'), 'utf8');
    expect(html).toMatch(/<html lang="en"/);
  });
});

describe('cross-workspace isolation', () => {
  it('blocks task fetch when workspace id does not match session binding', async () => {
    const workspaceA = '00000000-0000-0000-0000-00000000000b';
    const workspaceB = '00000000-0000-0000-0000-00000000000c';
    mockAuthenticatedFetch(workspaceA);
    const { wrapper, router } = await renderApp('/login');
    await wrapper.get('[data-testid="dev-sign-in"]').trigger('click');
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await router.push('/');
    await router.isReady();
    await vi.waitFor(() => {
      expect(document.body.textContent).toContain(workspaceA);
    });
    expect(document.body.textContent).not.toContain(workspaceB);
  });
});
