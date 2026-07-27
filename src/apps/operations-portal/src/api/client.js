const CSRF_HEADER = 'X-EdgeMint-CSRF-Token';
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
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const csrf = response.headers.get(CSRF_HEADER);
  if (csrf) csrfToken = csrf;
  const payload = await response.json();
  if (!response.ok) throw new ApiClientError(payload);
  return payload;
}

export const opsApi = {
  search: (view) => fetchJson(`/internal/operations/views/${view}`),
  submitAction: (body) => fetchJson('/internal/operations/actions:submit', { method: 'POST', body }),
  approve: (approvalId, body) =>
    fetchJson(`/internal/operations/approvals/${approvalId}:approve`, { method: 'POST', body }),
  activateBreakGlass: (body) => fetchJson('/internal/operations/break-glass:activate', { method: 'POST', body }),
  exportView: (body) => fetchJson('/internal/operations/exports:audited', { method: 'POST', body }),
};
