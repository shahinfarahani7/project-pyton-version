const portalBase = (import.meta.env.VITE_PORTAL_URL || 'http://127.0.0.1:5173').replace(/\/$/, '');

export const portalUrl = portalBase;
export const portalLoginUrl = `${portalBase}/login`;
export const portalRegisterUrl = `${portalBase}/register`;

// Same-origin path: the edge proxy sends /worker/* to worker-gateway, which serves the published APK.
export const workerApkUrl = import.meta.env.VITE_WORKER_APK_URL || '/worker/worker-app/release/apk';
