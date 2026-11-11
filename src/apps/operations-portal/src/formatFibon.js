const FIBON_ATOMIC_PER_TOKEN = 10_000;

export function formatFibon(atomic) {
  if (!Number.isInteger(atomic)) return '—';
  const whole = Math.floor(atomic / FIBON_ATOMIC_PER_TOKEN);
  const fraction = atomic % FIBON_ATOMIC_PER_TOKEN;
  if (fraction === 0) return `${whole} FIBON`;
  const digits = String(fraction).padStart(4, '0').replace(/0+$/, '');
  return `${whole}.${digits} FIBON`;
}
