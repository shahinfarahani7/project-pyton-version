import { reactive } from 'vue';

import { authApi, setCsrfToken } from '../api/client';

const initialState = {
  authenticated: false,
  sessionPublicId: null,
  workspaceId: null,
  authorizationGeneration: null,
  workspaces: [],
  permissions: [],
};

export const session = reactive({
  ...initialState,
  loginWithOidc() {
    window.location.assign('/auth/oidc/login');
  },
  async loginDev(workspaceId) {
    const created = await authApi.login({
      principalId: '00000000-0000-0000-0000-00000000000a',
      workspaceId,
      permissions: [
        'customer.tasks:read',
        'customer.tasks:write',
        'customer.webhooks:read',
        'customer.webhooks:write',
        'customer.apikeys:read',
        'customer.billing:read',
        'customer.team:read',
      ],
    });
    Object.assign(session, {
      authenticated: true,
      sessionPublicId: created.sessionPublicId,
      workspaceId: created.workspaceId,
      authorizationGeneration: created.authorizationGeneration,
      workspaces: [
        {
          id: workspaceId,
          name: 'Primary workspace',
          environment: 'production',
          status: 'active',
          version: 1,
        },
      ],
      permissions: [
        'customer.tasks:read',
        'customer.tasks:write',
        'customer.webhooks:read',
        'customer.webhooks:write',
        'customer.apikeys:read',
        'customer.billing:read',
        'customer.team:read',
      ],
    });
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
