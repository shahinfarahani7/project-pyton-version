<script setup>
import { ref } from 'vue';

import { opsApi } from '../api/client';
import { useSession } from '../auth/session';

const session = useSession();
const status = ref('');
</script>

<template>
  <section v-if="!session.hasPermission('operations.break_glass')" class="panel">
    <p>Break-glass permission required.</p>
  </section>
  <section v-else class="panel">
    <h1>Emergency controls</h1>
    <p>Break-glass access is time-bound, paged, recorded, and retrospectively reviewed.</p>
    <button
      type="button"
      @click="
        opsApi
          .activateBreakGlass({
            operatorId: session.operatorId,
            role: 'operator.break_glass',
            reasonCode: 'incident_response',
            ticketId: 'INC-BG-1',
          })
          .then((body) => {
            status = `Active until ${String(body.expiresAt)}`;
          })
          .catch((err) => {
            status = err.message;
          })
      "
    >
      Activate break-glass
    </button>
    <p v-if="status" role="status">{{ status }}</p>
  </section>
</template>
