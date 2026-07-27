import type { Problem } from './types';

const CSRF_HEADER = 'X-EdgeMint-CSRF-Token';
let csrfToken: string | null = null;

export class ApiClientError extends Error {
  readonly problem: Problem;
  constructor(problem: Problem) {
    super(problem.detail ?? problem.title);
    this.problem = problem;
  }
}

export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

export async function fetchJson<T>(
  path: string,
  options: { method?: string; body?: unknown; etag?: string } = {},
): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' };
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
  const payload = (await response.json()) as T | Problem;
  if (!response.ok) throw new ApiClientError(payload as Problem);
  return payload as T;
}

export const opsApi = {
  search: (view: string) => fetchJson<{ items: Record<string, unknown>[] }>(`/internal/operations/views/${view}`),
  submitAction: (body: Record<string, unknown>) =>
    fetchJson<Record<string, unknown>>('/internal/operations/actions:submit', { method: 'POST', body }),
  approve: (approvalId: string, body: Record<string, unknown>) =>
    fetchJson<Record<string, unknown>>(`/internal/operations/approvals/${approvalId}:approve`, {
      method: 'POST',
      body,
    }),
  activateBreakGlass: (body: Record<string, unknown>) =>
    fetchJson<Record<string, unknown>>('/internal/operations/break-glass:activate', { method: 'POST', body }),
  exportView: (body: Record<string, unknown>) =>
    fetchJson<Record<string, unknown>>('/internal/operations/exports:audited', { method: 'POST', body }),
};
