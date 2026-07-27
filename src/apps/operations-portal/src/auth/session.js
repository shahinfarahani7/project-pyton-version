import { reactive } from 'vue';

const ROLE_PERMISSIONS = {
  'operator.readonly': ['operations.read'],
  'operator.standard': ['operations.read', 'operations.mutate.low'],
  'operator.approver': ['operations.read', 'operations.mutate.low', 'operations.approve'],
  'operator.break_glass': ['operations.read', 'operations.mutate.low', 'operations.approve', 'operations.break_glass'],
};

export const session = reactive({
  authenticated: false,
  operatorId: null,
  role: null,
  mfaVerified: false,
  loginSso() {
    window.location.assign('/auth/oidc/login?audience=operations');
  },
  loginDev() {
    session.authenticated = true;
    session.operatorId = 'op_dev_1';
    session.role = 'operator.approver';
    session.mfaVerified = true;
  },
  logout() {
    session.authenticated = false;
    session.operatorId = null;
    session.role = null;
    session.mfaVerified = false;
  },
  hasPermission(permission) {
    if (!session.role) return false;
    return (ROLE_PERMISSIONS[session.role] ?? []).includes(permission);
  },
});

export function useSession() {
  return session;
}
