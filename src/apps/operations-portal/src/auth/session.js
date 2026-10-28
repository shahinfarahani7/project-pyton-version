import { reactive } from 'vue';

import { opsApi, setCsrfToken } from '../api/client';

let restorePromise = null;

function applySession(body) {
  session.authenticated = true;
  session.operatorId = body.operatorId;
  session.role = body.role;
  session.mfaVerified = Boolean(body.mfaVerified);
  session.permissions = body.permissions ?? [];
}

function clearSession() {
  session.authenticated = false;
  session.operatorId = null;
  session.role = null;
  session.mfaVerified = false;
  session.permissions = [];
  setCsrfToken(null);
}

async function signIn(request) {
  try {
    applySession(await request());
    session.error = null;
    session.errorCode = null;
  } catch (err) {
    clearSession();
    session.error = err.message;
    session.errorCode = err.problem?.code ?? null;
  }
}

export const session = reactive({
  authenticated: false,
  operatorId: null,
  role: null,
  mfaVerified: false,
  permissions: [],
  error: null,
  errorCode: null,
  loginSso() {
    window.location.assign('/internal/operations/session:sso');
  },
  loginDev() {
    return signIn(() => opsApi.devLogin({}));
  },
  loginPortal() {
    return signIn(() => opsApi.portalLogin());
  },
  restore() {
    restorePromise ??= opsApi
      .currentSession()
      .then(applySession)
      .catch(clearSession);
    return restorePromise;
  },
  async logout() {
    try {
      await opsApi.logout();
    } finally {
      clearSession();
      restorePromise = null;
    }
  },
  hasPermission(permission) {
    return session.permissions.includes(permission);
  },
});

export function useSession() {
  return session;
}
