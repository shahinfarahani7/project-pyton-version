/** Dev-only API/SSE logging (stripped from production builds via import.meta.env.DEV). */

const PREFIX = '[EdgeMint portal API]';

export function isDevApiLoggingEnabled() {
  return import.meta.env.DEV && import.meta.env.VITE_DEV_API_LOG !== 'false';
}

function previewBody(raw) {
  if (!raw) {
    return '(empty body)';
  }
  const trimmed = raw.trim();
  if (trimmed.length <= 480) {
    return trimmed;
  }
  return `${trimmed.slice(0, 480)}… (${trimmed.length} chars)`;
}

/** @returns {{ started: number, method: string, path: string } | null} */
export function devApiLogStart(method, path) {
  if (!isDevApiLoggingEnabled()) {
    return null;
  }
  const ctx = { started: performance.now(), method, path };
  console.info(`${PREFIX} → ${method} ${path}`);
  return ctx;
}

export function devApiLogResponse(ctx, response, raw) {
  if (!isDevApiLoggingEnabled() || !ctx) {
    return;
  }
  const ms = Math.round(performance.now() - ctx.started);
  const line = `${PREFIX} ← ${response.status} ${ctx.method} ${ctx.path} (${ms}ms)`;
  const body = previewBody(raw);
  if (response.ok) {
    console.info(line, body);
  } else {
    console.warn(line, body);
  }
}

export function devApiLogNetworkError(ctx, error) {
  if (!isDevApiLoggingEnabled() || !ctx) {
    return;
  }
  const ms = Math.round(performance.now() - ctx.started);
  console.error(
    `${PREFIX} ✗ no response ${ctx.method} ${ctx.path} (${ms}ms)`,
    error instanceof Error ? error.message : error,
  );
}

export function devSseLog(event, detail) {
  if (!isDevApiLoggingEnabled()) {
    return;
  }
  if (detail === undefined) {
    console.info(`${PREFIX} [SSE] ${event}`);
  } else {
    console.info(`${PREFIX} [SSE] ${event}`, detail);
  }
}
