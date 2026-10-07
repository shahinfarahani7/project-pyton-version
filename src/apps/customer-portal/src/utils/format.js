import { formatTaskType as formatTaskTypeLabel } from '../config/taskTypeCatalog';
import { resolveLocale } from '../i18n';

function firstTextLine(value) {
  const text = String(value ?? '').trim();
  if (!text) return '';
  const line = text.split(/\r?\n/).map((part) => part.trim()).find(Boolean) ?? text;
  return line.replace(/^#+\s*/, '');
}

export function taskListTitle(task) {
  const instruction = firstTextLine(task?.instructions);
  if (instruction) return instruction;
  const preview = firstTextLine(task?.inputPreview ?? task?.inputText);
  if (preview) return preview;
  const label = String(task?.inputLabel ?? '').trim();
  if (label && label !== 'Pasted text' && label !== 'Customer upload') return label;
  return formatTaskType(task);
}

export function formatTaskType(value, taskOrLocale) {
  if (value && typeof value === 'object' && value.taskType) {
    return value.taskTypeLabel ?? formatTaskTypeLabel(value.taskType, resolveLocale());
  }
  const locale = taskOrLocale === 'fa' || taskOrLocale === 'en' ? taskOrLocale : resolveLocale();
  return formatTaskTypeLabel(value, locale);
}

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

export function formatDateTime(value) {
  if (value == null || value === '') return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

const TASK_STATUS_GROUPS = {
  succeeded: 'done',
  completed: 'done',
  done: 'done',
  running: 'running',
  in_progress: 'running',
  queued: 'queued',
  pending: 'queued',
  cancelled: 'cancel',
  canceled: 'cancel',
  cancel: 'cancel',
};

export function taskStatusGroup(status) {
  const normalized = String(status ?? '').toLowerCase();
  return TASK_STATUS_GROUPS[normalized] ?? normalized;
}

export function statusTone(status) {
  const normalized = String(status ?? '').toLowerCase();
  if (['active', 'ready', 'succeeded', 'completed', 'done', 'paid', 'resolved', 'scanned'].includes(normalized)) {
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
