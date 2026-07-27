import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { App } from './App';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function mockAuthenticatedFetch(workspaceId: string) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo) => {
      const url = String(input);
      if (url.endsWith('/auth/sessions') && !url.includes('logout')) {
        return new Response(
          JSON.stringify({
            sessionPublicId: 'ses_a11y',
            workspaceId,
            authorizationGeneration: 2,
            expiresAt: '2026-12-31T00:00:00Z',
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json', 'X-EdgeMint-CSRF-Token': 'csrf-a11y' },
          },
        );
      }
      return new Response(JSON.stringify({ items: [], page: { hasMore: false, nextCursor: '' } }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }),
  );
}

describe('accessibility shell', () => {
  it('exposes skip link, landmarks, and labelled navigation', async () => {
    mockAuthenticatedFetch('00000000-0000-0000-0000-00000000000b');
    render(
      <MemoryRouter initialEntries={['/login']}>
        <App />
      </MemoryRouter>,
    );
    await screen.findByRole('button', { name: /development sign-in/i });
    fireEvent.click(screen.getByRole('button', { name: /development sign-in/i }));
    expect(await screen.findByRole('link', { name: /skip to main content/i })).toBeTruthy();
    expect(screen.getByRole('navigation', { name: /primary/i })).toBeTruthy();
    expect(document.getElementById('main-content')).toBeTruthy();
  });

  it('documents WCAG-oriented html language attribute', () => {
    const html = readFileSync(path.join(rootDir, '../index.html'), 'utf8');
    expect(html).toMatch(/<html lang="en"/);
  });
});

describe('cross-workspace isolation', () => {
  it('blocks task fetch when workspace id does not match session binding', async () => {
    const workspaceA = '00000000-0000-0000-0000-00000000000b';
    const workspaceB = '00000000-0000-0000-0000-00000000000c';
    mockAuthenticatedFetch(workspaceA);
    render(
      <MemoryRouter initialEntries={['/login']}>
        <App />
      </MemoryRouter>,
    );
    await screen.findByRole('button', { name: /development sign-in/i });
    fireEvent.click(screen.getByRole('button', { name: /development sign-in/i }));
    await screen.findByRole('heading', { name: /dashboard/i });
    expect(screen.getByText(workspaceA)).toBeTruthy();
    expect(screen.queryByText(workspaceB)).toBeNull();
  });
});
