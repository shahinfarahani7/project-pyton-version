import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it } from 'vitest';

import { App } from './App';

afterEach(() => cleanup());

function renderApp(route = '/login') {
  return render(
    <MemoryRouter initialEntries={[route]}>
      <App />
    </MemoryRouter>,
  );
}

describe('operations-portal', () => {
  it('renders SSO login without exposing provider tokens', () => {
    renderApp('/login');
    expect(screen.getByRole('heading', { name: /operator sign-in/i })).toBeTruthy();
    expect(document.body.textContent?.toLowerCase()).not.toContain('id_token');
  });

  it('shows MFA-gated shell after development sign-in', async () => {
    renderApp('/login');
    fireEvent.click(screen.getByRole('button', { name: /development sign-in/i }));
    expect(await screen.findByText(/MFA verified/i)).toBeTruthy();
    expect(screen.getByRole('navigation', { name: /operations/i })).toBeTruthy();
  });

  it('hides break-glass navigation without permission', async () => {
    renderApp('/login');
    fireEvent.click(screen.getByRole('button', { name: /development sign-in/i }));
    await screen.findByText(/MFA verified/i);
    expect(screen.queryByRole('link', { name: /emergency/i })).toBeNull();
  });
});
