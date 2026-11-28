<script setup>
import { onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import markUrl from '../assets/brand/fibonai-mark.png';
import { useSession } from '../auth/session';

const session = useSession();
const router = useRouter();
const route = useRoute();

const showDevSignIn = import.meta.env.DEV || import.meta.env.MODE === 'test';
const customerPortalUrl =
  import.meta.env.VITE_CUSTOMER_PORTAL_URL ?? `${window.location.protocol}//${window.location.hostname}:5173/login`;

const error = ref('');
const submitting = ref(false);
const status = ref('Checking sign-in…');
let bootstrapped = false;

async function run(action) {
  error.value = '';
  submitting.value = true;
  try {
    await action();
  } catch (err) {
    error.value = err instanceof Error ? err.message : String(err);
  } finally {
    submitting.value = false;
  }
}

function goToCustomerLogin() {
  window.location.assign(customerPortalUrl);
}

async function redeemHandoff(code) {
  await session.loginHandoff(code);
  if (!session.authenticated) {
    throw new Error(session.error ?? 'Admin handoff failed');
  }
  await router.replace('/');
}

function handoffCode() {
  return typeof route.query.handoff === 'string' ? route.query.handoff.trim() : '';
}

async function bootstrap() {
  if (session.authenticated) {
    await router.replace('/');
    return;
  }
  const code = handoffCode();
  if (code) {
    status.value = 'Opening admin console…';
    try {
      await redeemHandoff(code);
    } catch (err) {
      error.value = err instanceof Error ? err.message : String(err);
      status.value = '';
    }
    return;
  }
  status.value = '';
  // In unit tests keep the page mounted so development sign-in can be exercised.
  if (import.meta.env.MODE !== 'test') {
    goToCustomerLogin();
  }
}

function devSignIn() {
  run(async () => {
    await session.loginDev();
    if (!session.authenticated) throw new Error(session.error ?? 'Development sign-in failed');
    await router.replace('/');
  });
}

onMounted(async () => {
  bootstrapped = true;
  await bootstrap();
});

watch(
  () => route.query.handoff,
  async () => {
    if (!bootstrapped || session.authenticated) return;
    await bootstrap();
  },
);</script>

<template>
  <div v-if="!session.authenticated" class="login-screen">
    <section class="login-card" aria-labelledby="login-title">
      <header class="login-brand">
        <img :src="markUrl" alt="" />
        <span>FibonAI</span>
      </header>

      <h1 id="login-title">Admin console</h1>
      <p class="login-hint">
        Sign in once on the portal. Admin access is granted from the Admin access list.
      </p>

      <p v-if="status" class="login-hint" role="status">{{ status }}</p>
      <p v-if="error" class="login-error" role="alert">{{ error }}</p>

      <button type="button" class="primary" :disabled="submitting" @click="goToCustomerLogin">
        Go to portal sign-in
      </button>

      <button v-if="showDevSignIn" type="button" class="link-button dev-link" @click="devSignIn">
        Development sign-in
      </button>
    </section>
  </div>
</template>
