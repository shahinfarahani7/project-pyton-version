<script setup>
import { ref } from 'vue';

import { opsApi } from '../api/client';
import { useSession } from '../auth/session';

const session = useSession();
const approvalId = ref('');
const message = ref('');
</script>

<template>
  <section v-if="!session.hasPermission('operations.approve')" class="panel">
    <p>Approval permission required.</p>
  </section>
  <section v-else class="panel">
    <h1>Four-eyes approvals</h1>
    <p>High-risk actions require an independent approver. Self-approval is blocked.</p>
    <label>
      Approval ID
      <input v-model="approvalId" />
    </label>
    <button
      type="button"
      @click="
        opsApi
          .approve(approvalId, { approverId: session.operatorId, role: 'operator.approver' })
          .then((body) => {
            message = String(body.status ?? 'approved');
          })
          .catch((err) => {
            message = err.message;
          })
      "
    >
      Approve action
    </button>
    <p v-if="message" role="status">{{ message }}</p>
  </section>
</template>
