import { onBeforeUnmount, onMounted, ref } from 'vue';

export const POLL_INTERVAL_MS = 10_000;

export function usePolling(load, intervalMs = POLL_INTERVAL_MS) {
  const data = ref(null);
  const error = ref(null);
  const loading = ref(false);
  const updatedAt = ref(null);
  let timer = null;

  async function refresh() {
    loading.value = true;
    try {
      data.value = await load();
      error.value = null;
      updatedAt.value = new Date();
    } catch (err) {
      error.value = err?.message ?? 'Request failed';
    } finally {
      loading.value = false;
    }
  }

  onMounted(() => {
    refresh();
    timer = setInterval(refresh, intervalMs);
  });
  onBeforeUnmount(() => clearInterval(timer));

  return { data, error, loading, updatedAt, refresh };
}
