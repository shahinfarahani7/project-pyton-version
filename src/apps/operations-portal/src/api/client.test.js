import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

describe('operations api client', () => {
  it('keeps fetch helpers in plain JavaScript', () => {
    const source = readFileSync(path.join(rootDir, 'client.js'), 'utf8');
    expect(source).toContain('fetchJson');
    expect(source).toContain('opsApi');
    expect(source).not.toMatch(/:\s*Promise</);
  });
});

describe('content security policy', () => {
  it('restricts script sources to self', () => {
    const html = readFileSync(path.join(rootDir, '../../index.html'), 'utf8');
    expect(html).toContain("script-src 'self'");
  });
});
