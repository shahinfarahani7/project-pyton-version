import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';

import { authApi, setCsrfToken } from '../api/client';
import type { WorkspaceSummary } from '../api/types';

export type SessionState = {
  authenticated: boolean;
  sessionPublicId: string | null;
  workspaceId: string | null;
  authorizationGeneration: number | null;
  workspaces: WorkspaceSummary[];
  permissions: string[];
};

type SessionContextValue = SessionState & {
  loginWithOidc: () => void;
  loginDev: (workspaceId: string) => Promise<void>;
  logout: () => Promise<void>;
  switchWorkspace: (workspaceId: string) => Promise<void>;
  hasPermission: (permission: string) => boolean;
};

const SessionContext = createContext<SessionContextValue | null>(null);

const initialState: SessionState = {
  authenticated: false,
  sessionPublicId: null,
  workspaceId: null,
  authorizationGeneration: null,
  workspaces: [],
  permissions: [],
};

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SessionState>(initialState);

  const loginWithOidc = useCallback(() => {
    window.location.assign('/auth/oidc/login');
  }, []);

  const loginDev = useCallback(async (workspaceId: string) => {
    const session = await authApi.login({
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
    setState({
      authenticated: true,
      sessionPublicId: session.sessionPublicId,
      workspaceId: session.workspaceId,
      authorizationGeneration: session.authorizationGeneration,
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
  }, []);

  const logout = useCallback(async () => {
    await authApi.logout();
    setCsrfToken(null);
    setState(initialState);
  }, []);

  const switchWorkspace = useCallback(async (workspaceId: string) => {
    const session = await authApi.login({
      principalId: '00000000-0000-0000-0000-00000000000a',
      workspaceId,
      permissions: state.permissions,
    });
    setState((current) => ({
      ...current,
      workspaceId: session.workspaceId,
      authorizationGeneration: session.authorizationGeneration,
      sessionPublicId: session.sessionPublicId,
    }));
  }, [state.permissions]);

  const hasPermission = useCallback(
    (permission: string) => state.permissions.includes(permission),
    [state.permissions],
  );

  const value = useMemo(
    () => ({
      ...state,
      loginWithOidc,
      loginDev,
      logout,
      switchWorkspace,
      hasPermission,
    }),
    [state, loginWithOidc, loginDev, logout, switchWorkspace, hasPermission],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error('useSession must be used within SessionProvider');
  }
  return context;
}
