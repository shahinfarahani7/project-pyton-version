import { onMounted, onUnmounted, watch } from 'vue';

import { devSseLog } from '../api/devApiLog.js';

export function useTaskEventStream(getWorkspaceId, { enabled = () => true, onTaskEvent } = {}) {
  let source = null;

  function disconnect() {
    if (source) {
      source.close();
      source = null;
    }
  }

  function connect() {
    disconnect();
    if (!enabled()) {
      return;
    }
    const workspaceId = typeof getWorkspaceId === 'function' ? getWorkspaceId() : getWorkspaceId?.value;
    if (!workspaceId) {
      return;
    }

    const base = import.meta.env.VITE_API_BASE_URL ?? '';
    const streamPath = `/v1/workspaces/${workspaceId}/tasks/events`;
    devSseLog('connect', streamPath);
    source = new EventSource(`${base}${streamPath}`, {
      withCredentials: true,
    });
    source.addEventListener('open', () => {
      devSseLog('open', streamPath);
    });
    source.addEventListener('error', () => {
      devSseLog('error', { path: streamPath, readyState: source?.readyState });
    });
    source.addEventListener('task', (event) => {
      try {
        onTaskEvent?.(JSON.parse(event.data));
      } catch {
        devSseLog('malformed task payload', streamPath);
      }
    });
  }

  onMounted(() => {
    connect();
    if (getWorkspaceId?.value !== undefined) {
      watch(getWorkspaceId, connect);
    }
  });

  onUnmounted(disconnect);

  return { reconnect: connect, disconnect };
}
