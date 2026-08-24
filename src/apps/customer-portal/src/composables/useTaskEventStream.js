import { onMounted, onUnmounted, watch } from 'vue';

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
    source = new EventSource(`${base}/v1/workspaces/${workspaceId}/tasks/events`, {
      withCredentials: true,
    });
    source.addEventListener('task', (event) => {
      try {
        onTaskEvent?.(JSON.parse(event.data));
      } catch {
        // Ignore malformed SSE payloads.
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
