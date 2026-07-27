import path from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

const rootDir = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  plugins: [react()],
  build: { sourcemap: true },
  test: { environment: 'jsdom' },
  resolve: {
    alias: {
      '@generated/operations-api': path.resolve(rootDir, '../../../generated/typescript/openapi/operations_api.ts'),
    },
  },
});
