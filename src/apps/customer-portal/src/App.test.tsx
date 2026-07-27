import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { App } from './App';

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function renderApp(initialRoute = '/login') {
  return render(
    <MemoryRouter initialEntries={[initialRoute]}>
      <App />
    </MemoryRouter>,
  );
}

describe('customer-portal shell', () => {
  it('renders login journey without provider tokens in the DOM', () => {
    renderApp('/login');
    expect(screen.getByRole('heading', { name: /sign in/i })).toBeTruthy();
    expect(document.body.textContent).toContain('opaque BFF cookie');
    expect(document.body.textContent?.toLowerCase()).not.toContain('access_token');
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
  });

  it('redirects authenticated users away from login', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo) => {
        const url = String(input);
        if (url.endsWith('/auth/sessions') && !url.includes('logout')) {
          return new Response(
            JSON.stringify({
              sessionPublicId: 'ses_test',
              workspaceId: '00000000-0000-0000-0000-00000000000b',
              authorizationGeneration: 1,
              expiresAt: '2026-12-31T00:00:00Z',
            }),
            {
              status: 200,
              headers: { 'Content-Type': 'application/json', 'X-EdgeMint-CSRF-Token': 'csrf-test' },
            },
          );
        }
        return new Response(JSON.stringify({ items: [], page: { hasMore: false, nextCursor: '' } }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }),
    );

    renderApp('/login');
    fireEvent.click(screen.getByRole('button', { name: /development sign-in/i }));
    expect(await screen.findByRole('heading', { name: /dashboard/i })).toBeTruthy();
  });
});
