import vue from '@vitejs/plugin-vue';
import { defineConfig } from 'vitest/config';

import { devCspPlugin, devSameOriginApiDefine } from '../shared/vite-dev.js';

const devApiTarget = process.env.VITE_DEV_API_PROXY ?? 'http://127.0.0.1:8083';
const devAuthTarget = process.env.VITE_DEV_AUTH_PROXY ?? 'http://127.0.0.1:8080';

export default defineConfig(({ command }) => ({
  plugins: [vue(), ...(command === 'serve' ? [devCspPlugin()] : [])],
  define: command === 'serve' ? devSameOriginApiDefine() : undefined,
  server: {
    port: 5174,
    strictPort: true,
    proxy: {
      '/internal': { target: devApiTarget, changeOrigin: true },
      '/auth': { target: devAuthTarget, changeOrigin: true },
    },
  },
  build: { sourcemap: true },
  test: { environment: 'jsdom' },
}));
