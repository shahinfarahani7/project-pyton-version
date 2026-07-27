<script setup>
import { onMounted, ref } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { t } from '../i18n';

const session = useSession();
const usage = ref(null);
const balance = ref(null);
const invoices = ref(null);

onMounted(() => {
  if (!session.workspaceId || !session.hasPermission('customer.billing:read')) {
    return;
  }
  void Promise.all([
    portalApi.usage(session.workspaceId).then((body) => {
      usage.value = body;
    }),
    portalApi.balance(session.workspaceId).then((body) => {
      balance.value = body;
    }),
    portalApi.invoices(session.workspaceId).then((body) => {
      invoices.value = body;
    }),
  ]);
});
</script>

<template>
  <section class="panel">
    <h1>{{ t('nav.billing') }}</h1>
    <div class="grid">
      <article>
        <h2>Usage</h2>
        <p>{{ usage?.status ?? 'loading' }}</p>
      </article>
      <article>
        <h2>Balance</h2>
        <p>{{ balance?.status ?? 'loading' }}</p>
      </article>
      <article>
        <h2>Invoices</h2>
        <ul>
          <li v-for="invoice in invoices?.items ?? []" :key="invoice.id">
            {{ invoice.id }} · {{ invoice.status }}
          </li>
        </ul>
      </article>
    </div>
  </section>
</template>
