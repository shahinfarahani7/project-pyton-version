const portalBase = (import.meta.env.VITE_PORTAL_URL || 'http://127.0.0.1:5173').replace(/\/$/, '');

export const portalUrl = portalBase;
export const portalLoginUrl = `${portalBase}/login`;
export const portalRegisterUrl = `${portalBase}/register`;
