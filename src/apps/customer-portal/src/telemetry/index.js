const buffer = [];

export function trackEvent(name, attributes) {
  if (import.meta.env.VITE_TELEMETRY_ENABLED === 'false') {
    return;
  }
  buffer.push({ name, attributes });
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('edgemint:telemetry', { detail: { name, attributes } }));
  }
}

export function getTelemetryBuffer() {
  return [...buffer];
}

export function resetTelemetryBuffer() {
  buffer.length = 0;
}
