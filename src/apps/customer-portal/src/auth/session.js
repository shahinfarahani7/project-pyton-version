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
};

const portalPermissions = [
  'customer.tasks:read',
  'customer.tasks:write',
  'customer.webhooks:read',
  'customer.webhooks:write',
  'customer.apikeys:read',
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
    role: 'customer',
  });
}

export const session = reactive({
  ...initialState,
  async loginWithEmailOtp({ email, challengeId, code }) {
    await adoptSession(await authApi.verifyEmailOtp({ email, challengeId, code }));
  },
  async loginWithPassword({ email, password }) {
    await adoptSession(await authApi.loginWithPassword({ email, password }));
  },
  async signUpWithPassword({ email, password }) {
    await adoptSession(await authApi.signUp({ email, password }));
  },
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
