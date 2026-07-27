<script setup>
import { watch } from 'vue';
import { useRouter } from 'vue-router';

import { useSession } from '../auth/session';

const session = useSession();
const router = useRouter();

watch(
  () => session.authenticated,
  (authenticated) => {
    if (authenticated) {
      router.replace('/');
    }
  },
);
</script>

<template>
  <section v-if="!session.authenticated" class="panel login-panel">
    <h1>Operator sign-in</h1>
    <p>SSO with MFA completes on the server. Provider tokens never reach browser JavaScript.</p>
    <div class="actions">
      <button type="button" class="primary" @click="session.loginSso()">Continue with SSO + MFA</button>
      <button type="button" @click="session.loginDev()">Development sign-in</button>
    </div>
  </section>
</template>
