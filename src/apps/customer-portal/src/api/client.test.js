import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it, vi } from 'vitest';

import { fetchJson, getCsrfToken, setCsrfToken } from './client.js';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

describe('api client security', () => {
  it('uses generated Problem type shape on failure', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        new Response(
          JSON.stringify({
            type: 'https://problems.edgemint.io/auth-session-revoked',
            title: 'Session revoked',
            status: 401,
            code: 'AUTH_SESSION_REVOKED',
            traceId: 'trace_1',
          }),
          { status: 401, headers: { 'Content-Type': 'application/json' } },
        ),
      ),
    );
    await expect(fetchJson('/v1/me')).rejects.toMatchObject({
      problem: expect.objectContaining({ code: 'AUTH_SESSION_REVOKED' }),
    });
    vi.unstubAllGlobals();
  });

  it('stores CSRF token from BFF response header only in memory', async () => {
    setCsrfToken(null);
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        new Response(JSON.stringify({ status: 'ready' }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': 'csrf-header-value',
          },
        }),
      ),
    );
    await fetchJson('/auth/health');
    expect(getCsrfToken()).toBe('csrf-header-value');
    expect(localStorage.getItem('csrf')).toBeNull();
    vi.unstubAllGlobals();
  });

  it('sends If-Match for optimistic concurrency updates', async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ id: 'ws_1', version: 2 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    vi.stubGlobal('fetch', fetchMock);
    await fetchJson('/v1/workspaces/ws_1', { method: 'PATCH', body: { name: 'Renamed' }, etag: '"7"' });
    expect(fetchMock).toHaveBeenCalledWith(
      '/v1/workspaces/ws_1',
      expect.objectContaining({
        headers: expect.objectContaining({ 'If-Match': '"7"' }),
      }),
    );
    vi.unstubAllGlobals();
  });

  it('does not duplicate DTO definitions in portal source', () => {
    const clientSource = readFileSync(path.join(rootDir, 'client.js'), 'utf8');
    expect(clientSource).not.toMatch(/export type Task = \{/);
    expect(clientSource).toContain('fetchJson');
  });
});

describe('content security policy', () => {
  it('blocks inline script execution in index.html', () => {
    const html = readFileSync(path.join(rootDir, '../../index.html'), 'utf8');
    expect(html).toContain("script-src 'self'");
    expect(html).not.toContain('<script>');
    expect(html).toContain('type="module"');
  });
});
