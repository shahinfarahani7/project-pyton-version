import { reactive } from 'vue';

import { authApi, portalApi, setCsrfToken } from '../api/client';

const initialState = {
  authenticated: false,
  sessionPublicId: null,
  workspaceId: null,
  authorizationGeneration: null,
  workspaces: [],
  permissions: [],
  role: 'customer',
  operationsAdmin: false,
};

const portalPermissions = [
  'customer.tasks:read',
  'customer.tasks:write',
  'customer.webhooks:read',
  'customer.webhooks:write',
  'customer.apikeys:read',
  'customer.api-keys:read',
  'customer.api-keys:write',
  'customer.billing:read',
  'customer.team:read',
];

async function adoptSession(created) {
  const workspacesResponse = await portalApi.workspaces();
  Object.assign(session, {
    authenticated: true,
    sessionPublicId: created.sessionPublicId,
    workspaceId: created.workspaceId,
    authorizationGeneration: created.authorizationGeneration,
    workspaces: workspacesResponse.items ?? [],
    permissions: portalPermissions,
    role: created.role ?? 'customer',
    operationsAdmin: Boolean(created.operationsAdmin),
  });
}

export function operationsPortalLoginUrl() {
  const base =
    import.meta.env.VITE_OPERATIONS_PORTAL_URL ??
    `${window.location.protocol}//${window.location.hostname}:5174`;
  return base.replace(/\/login\/?$/, '').replace(/\/$/, '');
}

async function openOperationsConsole() {
  const handoff = await authApi.operationsHandoff();
  const target = `${operationsPortalLoginUrl()}/login?handoff=${encodeURIComponent(handoff.handoffCode)}`;
  window.location.assign(target);
}

export const session = reactive({
  ...initialState,
  async loginWithEmailOtp({ email, challengeId, code }) {
    await adoptSession(await authApi.verifyEmailOtp({ email, challengeId, code }));
    if (session.operationsAdmin) {
      await openOperationsConsole();
    }
  },
  async loginWithPassword({ email, password }) {
    await adoptSession(await authApi.loginWithPassword({ email, password }));
    if (session.operationsAdmin) {
      await openOperationsConsole();
    }
  },
  async signUpWithPassword({ email, password }) {
    await adoptSession(await authApi.signUp({ email, password }));
  },
  openOperationsConsole,
  async loginDev(workspaceId) {
    const created = await authApi.login({
      principalId: '00000000-0000-0000-0000-00000000000a',
      workspaceId,
      permissions: portalPermissions,
    });
    await adoptSession(created);
  },
  async logout() {
    await authApi.logout();
    setCsrfToken(null);
    Object.assign(session, initialState);
  },
  async switchWorkspace(workspaceId) {
    const updated = await authApi.login({
      principalId: '00000000-0000-0000-0000-00000000000a',
      workspaceId,
      permissions: session.permissions,
    });
    session.workspaceId = updated.workspaceId;
    session.authorizationGeneration = updated.authorizationGeneration;
    session.sessionPublicId = updated.sessionPublicId;
  },
  hasPermission(permission) {
    return session.permissions.includes(permission);
  },
});

export function useSession() {
  return session;
}
