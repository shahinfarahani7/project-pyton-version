const CSRF_HEADER = 'X-EdgeMint-CSRF-Token';

export class ApiClientError extends Error {
  constructor(problem) {
    super(problem.detail ?? problem.title);
    this.problem = problem;
  }
}

let csrfToken = null;

export function setCsrfToken(token) {
  csrfToken = token;
}

export function getCsrfToken() {
  return csrfToken;
}

function apiBaseUrl() {
  return import.meta.env.VITE_API_BASE_URL ?? '';
}

export async function fetchJson(path, options = {}) {
  const headers = {
    Accept: 'application/json',
  };
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  if (options.etag) {
    headers['If-Match'] = options.etag;
  }
  if (options.idempotencyKey) {
    headers['Idempotency-Key'] = options.idempotencyKey;
  }
  if (csrfToken && options.method && options.method !== 'GET') {
    headers[CSRF_HEADER] = csrfToken;
  }

  const response = await fetch(`${apiBaseUrl()}${path}`, {
    method: options.method ?? (options.body === undefined ? 'GET' : 'POST'),
    credentials: 'include',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  const csrfFromResponse = response.headers.get(CSRF_HEADER);
  if (csrfFromResponse) {
    csrfToken = csrfFromResponse;
  }

  if (response.status === 204) {
    return undefined;
  }

  const payload = await response.json();
  if (!response.ok) {
    throw new ApiClientError(payload);
  }
  return payload;
}

export const authApi = {
  health: () => fetchJson('/auth/health'),
  login: (body) => fetchJson('/auth/sessions', { method: 'POST', body }),
  logout: () => fetchJson('/auth/sessions/logout', { method: 'POST' }),
};

export const portalApi = {
  currentPrincipal: () => fetchJson('/v1/me'),
  workspaces: () => fetchJson('/v1/workspaces'),
  tasks: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/tasks`),
  task: (workspaceId, taskId) => fetchJson(`/v1/workspaces/${workspaceId}/tasks/${taskId}`),
  webhooks: () => fetchJson('/v1/webhook-endpoints'),
  apiKeys: () => fetchJson('/v1/api-keys'),
  usage: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/usage`),
  balance: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/credit-balance`),
  invoices: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/invoices`),
  disputes: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/disputes`),
};
