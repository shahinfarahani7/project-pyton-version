import { onMounted, ref } from 'vue';

export function useAsyncResource(loader, { enabled = () => true } = {}) {
  const data = ref(null);
  const error = ref(null);
  const loading = ref(false);

  async function refresh() {
    if (!enabled()) {
      return;
    }
    loading.value = true;
    error.value = null;
    try {
      data.value = await loader();
    } catch (err) {
      error.value = err?.message ?? 'Request failed';
      data.value = null;
    } finally {
      loading.value = false;
    }
  }

  onMounted(() => {
    void refresh();
  });

  return { data, error, loading, refresh };
}
