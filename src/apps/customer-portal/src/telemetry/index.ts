type TelemetryEvent = {
  name: string;
  attributes?: Record<string, string | number | boolean>;
};

const buffer: TelemetryEvent[] = [];

export function trackEvent(name: string, attributes?: Record<string, string | number | boolean>): void {
  if (import.meta.env.VITE_TELEMETRY_ENABLED === 'false') {
    return;
  }
  buffer.push({ name, attributes });
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('edgemint:telemetry', { detail: { name, attributes } }));
  }
}

export function getTelemetryBuffer(): TelemetryEvent[] {
  return [...buffer];
}

export function resetTelemetryBuffer(): void {
  buffer.length = 0;
}
