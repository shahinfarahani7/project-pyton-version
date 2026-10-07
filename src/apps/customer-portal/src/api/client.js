const CSRF_HEADER = 'X-CSRF-Token';

/** Normalize API/Problem+ and FastAPI error payloads into user-visible text. */
export function apiErrorMessage(problem) {
  if (problem == null) {
    return 'Request failed';
  }
  if (typeof problem === 'string') {
    return problem.trim() || 'Request failed';
  }
  if (typeof problem !== 'object') {
    return String(problem);
  }

  const detail = problem.detail;
  if (typeof detail === 'string' && detail.trim()) {
    return detail.trim();
  }
  if (Array.isArray(detail)) {
    const first = detail[0];
    if (first && typeof first === 'object') {
      const field = Array.isArray(first.loc) ? first.loc.filter(Boolean).join('.') : '';
      const message = first.msg ?? first.message;
      if (field && message) {
        return `${field}: ${message}`;
      }
      return message ?? JSON.stringify(first);
    }
    return String(first ?? problem.title ?? 'Request failed');
  }
  if (detail && typeof detail === 'object') {
    if (typeof detail.detail === 'string' && detail.detail.trim()) {
      return detail.detail.trim();
    }
    return detail.title ?? detail.code ?? problem.title ?? problem.code ?? 'Request failed';
  }

  return problem.title ?? problem.message ?? problem.code ?? 'Request failed';
}

export class ApiClientError extends Error {
  constructor(problem) {
    const normalized = typeof problem === 'string' ? { detail: problem } : problem ?? {};
    super(apiErrorMessage(normalized));
    this.problem = normalized;
    this.status = normalized.status;
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

  const raw = await response.text();
  let payload;
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    throw new ApiClientError({
      title: 'Request failed',
      detail: raw || `HTTP ${response.status}`,
      status: response.status,
    });
  }
  if (!response.ok) {
    throw new ApiClientError({ ...payload, status: response.status });
  }
  return payload;
}

export async function fetchForm(path, formData) {
  const headers = { Accept: 'application/json' };
  if (csrfToken) {
    headers[CSRF_HEADER] = csrfToken;
  }
  const response = await fetch(`${apiBaseUrl()}${path}`, {
    method: 'POST',
    credentials: 'include',
    headers,
    body: formData,
  });
  const csrfFromResponse = response.headers.get(CSRF_HEADER);
  if (csrfFromResponse) {
    csrfToken = csrfFromResponse;
  }
  const raw = await response.text();
  let payload;
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    throw new ApiClientError({
      title: 'Request failed',
      detail: raw || `HTTP ${response.status}`,
      status: response.status,
    });
  }
  if (!response.ok) {
    throw new ApiClientError({ ...payload, status: response.status });
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
  createTask: (workspaceId, payload) => {
    const { taskType, inputText, inputFile, instructions, summarizeOptions } = payload;
    if (inputFile) {
      const formData = new FormData();
      formData.append('taskType', taskType);
      if (instructions) {
        formData.append('instructions', instructions);
      }
      if (inputText) {
        formData.append('inputText', inputText);
      } else if (instructions) {
        formData.append('inputText', instructions);
      }
      if (summarizeOptions) {
        formData.append('summarizeOptions', JSON.stringify(summarizeOptions));
      }
      formData.append('inputFile', inputFile);
      return fetchForm(`/v1/workspaces/${workspaceId}/tasks`, formData);
    }
    return fetchJson(`/v1/workspaces/${workspaceId}/tasks`, {
      method: 'POST',
      body: {
        taskType,
        inputText,
        instructions,
        ...(summarizeOptions ? { summarizeOptions } : {}),
      },
    });
  },
  task: (workspaceId, taskId) => fetchJson(`/v1/workspaces/${workspaceId}/tasks/${taskId}`),
  cancelTask: (workspaceId, taskId) =>
    fetchJson(`/v1/workspaces/${workspaceId}/tasks/${taskId}:cancel`, {
      method: 'POST',
    }),
  taskTypes: (query) => {
    const params = new URLSearchParams();
    if (query?.q) {
      params.set('q', query.q);
    }
    if (query?.locale) {
      params.set('locale', query.locale);
    }
    const suffix = params.toString() ? `?${params.toString()}` : '';
    return fetchJson(`/v1/task-types${suffix}`);
  },
  webhooks: () => fetchJson('/v1/webhook-endpoints'),
  apiKeys: () => fetchJson('/v1/api-keys'),
  usage: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/usage`),
  balance: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/credit-balance`),
  wallets: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/wallets`),
  addWallet: (workspaceId, body) =>
    fetchJson(`/v1/workspaces/${workspaceId}/wallets`, {
      method: 'POST',
      body,
    }),
  invoices: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/invoices`),
  disputes: (workspaceId) => fetchJson(`/v1/workspaces/${workspaceId}/disputes`),
};
