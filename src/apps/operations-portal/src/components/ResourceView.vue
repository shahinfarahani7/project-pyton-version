<script setup>
import { onMounted, ref } from 'vue';

import { opsApi } from '../api/client';

const props = defineProps({
  view: { type: String, required: true },
  title: { type: String, required: true },
});

const items = ref([]);

onMounted(() => {
  opsApi
    .search(props.view)
    .then((body) => {
      items.value = body.items;
    })
    .catch(() => {
      items.value = [];
    });
});
</script>

<template>
  <section class="panel">
    <h1>{{ title }}</h1>
    <table>
      <thead>
        <tr>
          <th scope="col">ID</th>
          <th scope="col">Status</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="item in items" :key="String(item.id)">
          <td>{{ String(item.id) }}</td>
          <td>{{ String(item.status ?? 'unknown') }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
