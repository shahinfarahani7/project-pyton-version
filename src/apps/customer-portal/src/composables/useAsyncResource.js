import { onMounted, onUnmounted, ref } from 'vue';

export function useAsyncResource(loader, { enabled = () => true } = {}) {
  const data = ref(null);
  const error = ref(null);
  const loading = ref(false);

  async function refresh(options = {}) {
    const silent = options.silent === true;
    if (!enabled()) {
      return;
    }
    if (!silent) {
      loading.value = true;
    }
    error.value = null;
    try {
      data.value = await loader();
    } catch (err) {
      error.value = err?.message ?? 'Request failed';
      if (!silent) {
        data.value = null;
      }
    } finally {
      if (!silent) {
        loading.value = false;
      }
    }
  }

  onMounted(() => {
    void refresh();
  });

  return { data, error, loading, refresh };
}
