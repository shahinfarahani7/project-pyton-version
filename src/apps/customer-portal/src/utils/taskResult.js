export function truncateText(text, maxLength = 72) {
  if (!text) {
    return '';
  }
  const normalized = String(text).replace(/\s+/g, ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, maxLength - 1)}…`;
}

export function taskResultState(task) {
  const lifecycle = String(task?.lifecycleStatus ?? '').toLowerCase();

  if (['succeeded', 'completed'].includes(lifecycle)) {
    if (task?.resultPreview) {
      return { kind: 'text', text: task.resultPreview };
    }
    if (task?.resultArtifactUrl) {
      return { kind: 'file', url: task.resultArtifactUrl };
    }
    return { kind: 'none' };
  }

  if (['failed'].includes(lifecycle)) {
    return { kind: 'failed' };
  }

  if (['running', 'queued', 'in_progress', 'pending', 'draft'].includes(lifecycle)) {
    return { kind: 'pending' };
  }

  return { kind: 'none' };
}

export function taskResultDownloadName(task) {
  if (task?.inputLabel) {
    return `result-${task.inputLabel}`;
  }
  if (task?.id) {
    return `result-${task.id}`;
  }
  return 'result';
}
