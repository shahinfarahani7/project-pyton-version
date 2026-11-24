const portalBase = (import.meta.env.VITE_PORTAL_URL || 'http://171.22.26.64:3000').replace(/\/$/, '');
const workerGatewayBase = (import.meta.env.VITE_WORKER_GATEWAY_URL || 'https://fibonai.app/worker').replace(/\/$/, '');

export const portalUrl = portalBase;
export const portalLoginUrl = `${portalBase}/login`;
export const portalRegisterUrl = `${portalBase}/register`;

export const workerApkUrl = import.meta.env.VITE_WORKER_APK_URL || `${workerGatewayBase}/worker-app/release/apk`;
export const workerReleaseUrl = `${workerGatewayBase}/worker-app/release`;
