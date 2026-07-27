import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

export type OperatorSession = {
  authenticated: boolean;
  operatorId: string | null;
  role: string | null;
  mfaVerified: boolean;
};

type SessionContextValue = OperatorSession & {
  loginSso: () => void;
  loginDev: () => void;
  logout: () => void;
  hasPermission: (permission: string) => boolean;
};

const ROLE_PERMISSIONS: Record<string, string[]> = {
  'operator.readonly': ['operations.read'],
  'operator.standard': ['operations.read', 'operations.mutate.low'],
  'operator.approver': ['operations.read', 'operations.mutate.low', 'operations.approve'],
  'operator.break_glass': ['operations.read', 'operations.mutate.low', 'operations.approve', 'operations.break_glass'],
};

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<OperatorSession>({
    authenticated: false,
    operatorId: null,
    role: null,
    mfaVerified: false,
  });

  const value = useMemo(
    () => ({
      ...state,
      loginSso: () => {
        window.location.assign('/auth/oidc/login?audience=operations');
      },
      loginDev: () => {
        setState({
          authenticated: true,
          operatorId: 'op_dev_1',
          role: 'operator.approver',
          mfaVerified: true,
        });
      },
      logout: () => setState({ authenticated: false, operatorId: null, role: null, mfaVerified: false }),
      hasPermission: (permission: string) => {
        if (!state.role) return false;
        return (ROLE_PERMISSIONS[state.role] ?? []).includes(permission);
      },
    }),
    [state],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useSession requires SessionProvider');
  return ctx;
}
