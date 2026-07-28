export function formatMicroEur(micro) {
  if (micro == null) return '—';
  return new Intl.NumberFormat('en-EU', { style: 'currency', currency: 'EUR' }).format(micro / 1_000_000);
}

export function formatNumber(value) {
  if (value == null) return '—';
  return new Intl.NumberFormat().format(value);
}

export function formatBytes(bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

export function statusTone(status) {
  const normalized = String(status ?? '').toLowerCase();
  if (['active', 'ready', 'succeeded', 'completed', 'paid', 'resolved', 'scanned'].includes(normalized)) {
    return 'success';
  }
  if (['running', 'in_progress', 'open', 'queued', 'pending', 'draft'].includes(normalized)) {
    return 'warning';
  }
  if (['paused', 'not_started'].includes(normalized)) {
    return 'neutral';
  }
  if (['failed', 'revoked', 'locked'].includes(normalized)) {
    return 'error';
  }
  return 'neutral';
}
