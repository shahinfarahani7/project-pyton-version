/** Dev-only Vite helpers: same-origin API proxy + relaxed CSP for HMR. */

export function devCspPlugin(extra = '') {
  return {
    name: 'edgemint-dev-csp',
    transformIndexHtml: {
      order: 'pre',
      handler(html, ctx) {
        if (!ctx.server) {
          return html;
        }
        const directives = [
          "default-src 'self'",
          "script-src 'self' 'unsafe-eval'",
          "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
          "font-src 'self' https://fonts.gstatic.com",
          "img-src 'self' data:",
          "connect-src 'self' ws: wss:",
          "base-uri 'self'",
          "form-action 'self'",
          extra,
        ]
          .filter(Boolean)
          .join('; ');
        return html.replace(
          /<meta\s+http-equiv="Content-Security-Policy"\s+content="[^"]*"\s*\/>/,
          `<meta http-equiv="Content-Security-Policy" content="${directives}" />`,
        );
      },
    },
  };
}

export function devSameOriginApiDefine() {
  return {
    'import.meta.env.VITE_API_BASE_URL': JSON.stringify(''),
  };
}
