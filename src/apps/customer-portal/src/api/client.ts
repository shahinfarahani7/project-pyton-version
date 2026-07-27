import type { Problem } from './types';

const CSRF_HEADER = 'X-EdgeMint-CSRF-Token';

export class ApiClientError extends Error {
  readonly problem: Problem;

  constructor(problem: Problem) {
    super(problem.detail ?? problem.title);
    this.problem = problem;
  }
}

export type FetchJsonOptions = {
  method?: string;
  body?: unknown;
  etag?: string;
  idempotencyKey?: string;
};

let csrfToken: string | null = null;

export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

export function getCsrfToken(): string | null {
  return csrfToken;
}

function apiBaseUrl(): string {
  return import.meta.env.VITE_API_BASE_URL ?? '';
}

export async function fetchJson<T>(path: string, options: FetchJsonOptions = {}): Promise<T> {
  const headers: Record<string, string> = {
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
    return undefined as T;
  }

  const payload = (await response.json()) as T | Problem;
  if (!response.ok) {
    throw new ApiClientError(payload as Problem);
  }
  return payload as T;
}

export const authApi = {
  health: () => fetchJson<{ status: string; bff: string }>('/auth/health'),
  login: (body: { principalId: string; workspaceId: string; permissions: string[] }) =>
    fetchJson<{ sessionPublicId: string; workspaceId: string; authorizationGeneration: number; expiresAt: string }>(
      '/auth/sessions',
      { method: 'POST', body },
    ),
  logout: () => fetchJson<{ status: string }>('/auth/sessions/logout', { method: 'POST' }),
};

export const portalApi = {
  currentPrincipal: () => fetchJson<import('./types').GetCurrentPrincipalResponse>('/v1/me'),
  workspaces: () => fetchJson<import('./types').ListWorkspacesResponse>('/v1/workspaces'),
  tasks: (workspaceId: string) =>
    fetchJson<import('./types').ListTasksResponse>(`/v1/workspaces/${workspaceId}/tasks`),
  task: (workspaceId: string, taskId: string) =>
    fetchJson<import('./types').Task>(`/v1/workspaces/${workspaceId}/tasks/${taskId}`),
  webhooks: () => fetchJson<import('./types').ListWebhookEndpointsResponse>('/v1/webhook-endpoints'),
  apiKeys: () => fetchJson<import('./types').ListApiKeysResponse>('/v1/api-keys'),
  usage: (workspaceId: string) =>
    fetchJson<import('./types').GetUsageResponse>(`/v1/workspaces/${workspaceId}/usage`),
  balance: (workspaceId: string) =>
    fetchJson<import('./types').GetCreditBalanceResponse>(`/v1/workspaces/${workspaceId}/credit-balance`),
  invoices: (workspaceId: string) =>
    fetchJson<import('./types').ListInvoicesResponse>(`/v1/workspaces/${workspaceId}/invoices`),
  disputes: (workspaceId: string) =>
    fetchJson<import('./types').ListDisputesResponse>(`/v1/workspaces/${workspaceId}/disputes`),
};
