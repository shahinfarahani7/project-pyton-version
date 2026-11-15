const CSRF_HEADER = 'X-CSRF-Token';
let csrfToken = null;

export class ApiClientError extends Error {
  constructor(problem) {
    super(problem.detail ?? problem.title);
    this.problem = problem;
  }
}

export function setCsrfToken(token) {
  csrfToken = token;
}

export async function fetchJson(path, options = {}) {
  const headers = { Accept: 'application/json' };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  if (options.etag) headers['If-Match'] = options.etag;
  if (csrfToken && options.method && options.method !== 'GET') headers[CSRF_HEADER] = csrfToken;

  const response = await fetch(`${import.meta.env.VITE_API_BASE_URL ?? ''}${path}`, {
    method: options.method ?? (options.body ? 'POST' : 'GET'),
    credentials: 'include',
    cache: 'no-store',
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const csrf = response.headers.get(CSRF_HEADER);
  if (csrf) csrfToken = csrf;
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new ApiClientError({
      status: response.status,
      code: 'SERVICE_UNAVAILABLE',
      title: `Service unavailable (HTTP ${response.status}). Is the backend running?`,
    });
  }
  if (!response.ok) throw new ApiClientError(payload);
  return payload;
}

export const authApi = {
  loginWithPassword: (body) => fetchJson('/auth/email-password', { method: 'POST', body }),
  requestEmailOtp: (email) => fetchJson('/auth/email-otp/challenges', { method: 'POST', body: { email } }),
  verifyEmailOtp: (body) => fetchJson('/auth/email-otp/verify', { method: 'POST', body }),
};

export const opsApi = {
  devLogin: (body) => fetchJson('/internal/operations/session:dev-login', { method: 'POST', body }),
  portalLogin: () => fetchJson('/internal/operations/session:portal', { method: 'POST' }),
  currentSession: () => fetchJson('/internal/operations/session'),
  logout: () => fetchJson('/internal/operations/session:logout', { method: 'POST' }),
  search: (view) => fetchJson(`/internal/operations/views/${view}`),
  workerDevices: () => fetchJson('/internal/operations/worker-devices'),
  taskMonitor: () => fetchJson('/internal/operations/task-monitor'),
  cancelTask: (taskId) => fetchJson(`/internal/operations/tasks/${encodeURIComponent(taskId)}:cancel`, { method: 'POST' }),
  overview: () => fetchJson('/internal/operations/overview'),
  submitAction: (body) => fetchJson('/internal/operations/actions:submit', { method: 'POST', body }),
  approve: (approvalId, body) =>
    fetchJson(`/internal/operations/approvals/${approvalId}:approve`, { method: 'POST', body }),
  activateBreakGlass: (body) => fetchJson('/internal/operations/break-glass:activate', { method: 'POST', body }),
  exportView: (body) => fetchJson('/internal/operations/exports:audited', { method: 'POST', body }),
};
