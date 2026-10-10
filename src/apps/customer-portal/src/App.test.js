import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

import App from './App.vue';
import { session } from './auth/session';
import AppShell from './components/AppShell.vue';
import AccountPage from './pages/AccountPage.vue';
import ApiKeysPage from './pages/ApiKeysPage.vue';
import BillingPage from './pages/BillingPage.vue';
import DashboardPage from './pages/DashboardPage.vue';
import FilesPage from './pages/FilesPage.vue';
import LoginPage from './pages/LoginPage.vue';
import MorePage from './pages/MorePage.vue';
import TaskDetailPage from './pages/TaskDetailPage.vue';
import TaskChatPage from './pages/TaskChatPage.vue';
import UsagePage from './pages/UsagePage.vue';
import WalletPage from './pages/WalletPage.vue';

function resetSession() {
  Object.assign(session, {
    authenticated: false,
    sessionPublicId: null,
    workspaceId: null,
    authorizationGeneration: null,
    workspaces: [],
    permissions: [],
    role: 'customer',
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
          { path: 'tasks', name: 'tasks', component: TaskChatPage },
          { path: 'tasks/:id', name: 'task-detail', component: TaskDetailPage },
          { path: 'usage', name: 'usage', component: UsagePage },
          { path: 'billing', name: 'billing', component: BillingPage },
          { path: 'more', name: 'more', component: MorePage },
          { path: 'files', name: 'files', component: FilesPage },
          { path: 'api-keys', name: 'api-keys', component: ApiKeysPage },
          { path: 'wallet', name: 'wallet', component: WalletPage },
          { path: 'account', name: 'account', component: AccountPage },
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

function otpFetchMock({ rejectCode = null } = {}) {
  return vi.fn(async (input, init) => {
    const url = String(input);
    if (url.endsWith('/auth/email-otp/challenges')) {
      return new Response(
        JSON.stringify({
          challengeId: 'otp_test',
          expiresInSeconds: 300,
          emailDispatched: false,
          devCode: '123456',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }
    if (url.endsWith('/auth/email-otp/verify')) {
      const body = JSON.parse(init?.body ?? '{}');
      if (rejectCode && body.code === rejectCode) {
        return new Response(
          JSON.stringify({ detail: { code: 'AUTH_INVALID_CREDENTIAL', title: 'Invalid credentials', detail: 'The code is invalid or expired.' } }),
          { status: 401, headers: { 'Content-Type': 'application/json' } },
        );
      }
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
  });
}

async function submitEmailOtp(wrapper, code = '123456') {
  await wrapper.get('[data-testid="login-method-otp"]').trigger('click');
  await wrapper.get('[data-testid="login-email"]').setValue('dev-user@edgemint.local');
  await wrapper.get('[data-testid="login-email-form"]').trigger('submit');
  await vi.waitFor(() => {
    expect(wrapper.find('[data-testid="login-otp"]').exists()).toBe(true);
  });
  await wrapper.get('[data-testid="login-otp"]').setValue(code);
  await wrapper.get('[data-testid="login-otp-form"]').trigger('submit');
}

describe('customer-portal shell', () => {
  it('renders login journey without provider tokens in the DOM', async () => {
    await renderApp('/login');
    expect(document.body.textContent).toMatch(/sign in/i);
    expect(document.body.textContent).not.toContain('Admin login');
    expect(document.body.textContent).not.toContain('Continue with SSO');
    expect(document.body.textContent).toContain('Password');
    expect(document.body.textContent).toContain('One-time code');
    expect(document.body.textContent).toContain('opaque BFF cookie');
    expect(document.body.textContent?.toLowerCase()).not.toContain('access_token');
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
    expect(document.querySelector('[data-testid="login-email"]')).toBeTruthy();
  });

  it('redirects authenticated users away from login after email OTP', async () => {
    vi.stubGlobal('fetch', otpFetchMock());

    const { wrapper } = await renderApp('/login');
    await submitEmailOtp(wrapper);
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/dashboard/i);
    });
  });

  it('signs in with the development password', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input, init) => {
        const url = String(input);
        if (url.endsWith('/auth/email-password')) {
          const body = JSON.parse(init?.body ?? '{}');
          if (body.password !== 'edgemint-dev') {
            return new Response(
              JSON.stringify({
                detail: {
                  code: 'AUTH_INVALID_CREDENTIAL',
                  title: 'Invalid credentials',
                  detail: 'The email or password is incorrect.',
                },
              }),
              { status: 401, headers: { 'Content-Type': 'application/json' } },
            );
          }
          return new Response(
            JSON.stringify({
              sessionPublicId: 'ses_password',
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
    await wrapper.get('[data-testid="login-password"]').setValue('edgemint-dev');
    await wrapper.get('[data-testid="login-password-form"]').trigger('submit');
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/dashboard/i);
    });
  });

  it('stays on login when the password is rejected', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input) => {
        const url = String(input);
        if (url.endsWith('/auth/email-password')) {
          return new Response(
            JSON.stringify({
              detail: {
                code: 'AUTH_INVALID_CREDENTIAL',
                title: 'Invalid credentials',
                detail: 'The email or password is incorrect.',
              },
            }),
            { status: 401, headers: { 'Content-Type': 'application/json' } },
          );
        }
        return new Response(JSON.stringify({}), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }),
    );
    const { wrapper } = await renderApp('/login');
    await wrapper.get('[data-testid="login-password"]').setValue('wrong-password');
    await wrapper.get('[data-testid="login-password-form"]').trigger('submit');
    await vi.waitFor(() => {
      expect(document.body.textContent).toContain('The email or password is incorrect.');
    });
    expect(session.authenticated).toBe(false);
    expect(wrapper.find('[data-testid="login-password"]').exists()).toBe(true);
  });

  it('stays on login when the one-time code is rejected', async () => {
    vi.stubGlobal('fetch', otpFetchMock({ rejectCode: '000000' }));
    const { wrapper } = await renderApp('/login');
    await submitEmailOtp(wrapper, '000000');
    await vi.waitFor(() => {
      expect(document.body.textContent).toContain('The code is invalid or expired.');
    });
    expect(session.authenticated).toBe(false);
    expect(wrapper.find('[data-testid="login-otp"]').exists()).toBe(true);
  });

  it('creates an account and opens the dashboard', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input, init) => {
        const url = String(input);
        if (url.endsWith('/auth/email-signup')) {
          const body = JSON.parse(init?.body ?? '{}');
          if (body.email !== 'new-user@example.com' || body.password !== 'new-password') {
            return new Response(
              JSON.stringify({
                detail: {
                  code: 'AUTH_INVALID_CREDENTIAL',
                  title: 'Invalid credentials',
                  detail: 'Could not create the account.',
                },
              }),
              { status: 422, headers: { 'Content-Type': 'application/json' } },
            );
          }
          return new Response(
            JSON.stringify({
              sessionPublicId: 'ses_signup',
              workspaceId: '00000000-0000-0000-0000-00000000000b',
              authorizationGeneration: 1,
              expiresAt: '2026-12-31T00:00:00Z',
              role: 'customer',
            }),
            {
              status: 201,
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
    await wrapper.get('[data-testid="login-show-signup"]').trigger('click');
    expect(document.body.textContent).toContain('Create account');
    expect(wrapper.get('[data-testid="login-password-rules"]').text()).toContain('At least 8 characters');
    expect(wrapper.get('[data-testid="login-password-rules"] li').classes()).not.toContain('is-met');
    expect(wrapper.get('[data-testid="login-email"]').element.value).toBe('');
    await wrapper.get('[data-testid="login-email"]').setValue('new-user@example.com');
    await wrapper.get('[data-testid="login-password"]').setValue('new-password');
    expect(wrapper.get('[data-testid="login-password-rules"] li').classes()).toContain('is-met');
    await wrapper.get('[data-testid="login-confirm-password"]').setValue('other-password');
    await wrapper.get('[data-testid="login-signup-form"]').trigger('submit');
    expect(document.body.textContent).toContain('Passwords do not match.');
    await wrapper.get('[data-testid="login-confirm-password"]').setValue('new-password');
    await wrapper.get('[data-testid="login-signup-form"]').trigger('submit');
    await vi.waitFor(() => {
      expect(session.authenticated).toBe(true);
    });
    await vi.waitFor(() => {
      expect(document.body.textContent).toMatch(/dashboard/i);
    });
  });
});
