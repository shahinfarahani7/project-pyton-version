import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

describe('operations api types', () => {
  it('re-exports generated operations OpenAPI types', () => {
    const source = readFileSync(path.join(rootDir, 'types.ts'), 'utf8');
    expect(source).toContain('generated/typescript/openapi/operations_api');
    expect(source).toContain('OperatorAction');
  });
});

describe('content security policy', () => {
  it('restricts script sources to self', () => {
    const html = readFileSync(path.join(rootDir, '../../index.html'), 'utf8');
    expect(html).toContain("script-src 'self'");
  });
});
