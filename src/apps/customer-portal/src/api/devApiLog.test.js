import { describe, expect, it, vi } from 'vitest';

import { devApiLogNetworkError, devApiLogResponse, devApiLogStart, isDevApiLoggingEnabled } from './devApiLog.js';

describe('devApiLog', () => {
  it('is disabled when VITE_DEV_API_LOG is false', () => {
    vi.stubEnv('VITE_DEV_API_LOG', 'false');
    expect(isDevApiLoggingEnabled()).toBe(false);
    vi.unstubAllEnvs();
  });

  it('does not throw when logging is disabled', () => {
    vi.stubEnv('VITE_DEV_API_LOG', 'false');
    expect(devApiLogStart('GET', '/v1/me')).toBeNull();
    devApiLogResponse(null, new Response('', { status: 200 }), '{}');
    devApiLogNetworkError(null, new Error('network'));
    vi.unstubAllEnvs();
  });
});
