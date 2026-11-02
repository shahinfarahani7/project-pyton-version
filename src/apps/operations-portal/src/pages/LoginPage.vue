<script setup>
import { ref, watch } from 'vue';
import { useRouter } from 'vue-router';

import { authApi } from '../api/client';
import markUrl from '../assets/brand/fibonai-mark.png';
import { useSession } from '../auth/session';

const session = useSession();
const router = useRouter();

const showDevSignIn = import.meta.env.DEV || import.meta.env.MODE === 'test';
const customerPortalUrl =
  import.meta.env.VITE_CUSTOMER_PORTAL_URL ?? `${window.location.protocol}//${window.location.hostname}:5173/login`;

const audience = ref('admin');
const method = ref('password');
const step = ref('email');
const email = ref('');
const password = ref('');
const code = ref('');
const challengeId = ref('');
const devCode = ref('');
const error = ref('');
const submitting = ref(false);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

watch(
  () => session.authenticated,
  (authenticated) => {
    if (authenticated) router.replace('/');
  },
);

function selectMethod(next) {
  method.value = next;
  step.value = 'email';
  error.value = '';
}

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

async function enterAdmin() {
  await session.loginPortal();
  if (!session.authenticated) throw new Error(session.error ?? 'Admin sign-in failed');
}

function submitPassword() {
  if (!EMAIL_RE.test(email.value.trim())) {
    error.value = 'Enter a valid email address.';
    return;
  }
  if (!password.value) {
    error.value = 'Enter your password.';
    return;
  }
  run(async () => {
    await authApi.loginWithPassword({ email: email.value.trim(), password: password.value });
    password.value = '';
    await enterAdmin();
  });
}

function requestCode() {
  if (!EMAIL_RE.test(email.value.trim())) {
    error.value = 'Enter a valid email address.';
    return;
  }
  run(async () => {
    const issued = await authApi.requestEmailOtp(email.value.trim());
    challengeId.value = issued.challengeId;
    devCode.value = typeof issued.devCode === 'string' ? issued.devCode : '';
    code.value = '';
    step.value = 'otp';
  });
}

function verifyCode() {
  if (!/^\d{6}$/.test(code.value.trim())) {
    error.value = 'Enter the 6-digit code.';
    return;
  }
  run(async () => {
    await authApi.verifyEmailOtp({ email: email.value.trim(), challengeId: challengeId.value, code: code.value.trim() });
    await enterAdmin();
  });
}

function devSignIn() {
  run(async () => {
    await session.loginDev();
    if (!session.authenticated) throw new Error(session.error ?? 'Development sign-in failed');
  });
}
</script>

<template>
  <div v-if="!session.authenticated" class="login-screen">
    <section class="login-card" aria-labelledby="login-title">
      <header class="login-brand">
        <img :src="markUrl" alt="" />
        <span>FibonAI</span>
      </header>

      <div class="segmented" role="tablist" aria-label="Account type">
        <button
          type="button"
          role="tab"
          :aria-selected="audience === 'admin'"
          :class="{ active: audience === 'admin' }"
          @click="audience = 'admin'; error = ''"
        >
          Admin
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="audience === 'customer'"
          :class="{ active: audience === 'customer' }"
          @click="audience = 'customer'; error = ''"
        >
          Customer
        </button>
      </div>

      <template v-if="audience === 'admin'">
        <h1 id="login-title">Admin sign-in</h1>
        <p class="login-hint">Only accounts on the operations admin list can enter.</p>

        <div class="method-switch">
          <button type="button" :class="{ active: method === 'password' }" @click="selectMethod('password')">
            Password
          </button>
          <button type="button" :class="{ active: method === 'otp' }" @click="selectMethod('otp')">
            Email code
          </button>
        </div>

        <form v-if="method === 'password'" class="login-form" @submit.prevent="submitPassword">
          <label>
            Email
            <input v-model="email" type="email" autocomplete="username" required />
          </label>
          <label>
            Password
            <input v-model="password" type="password" autocomplete="current-password" required />
          </label>
          <button type="submit" class="primary" :disabled="submitting">
            {{ submitting ? 'Signing in…' : 'Sign in as admin' }}
          </button>
        </form>

        <form v-else-if="step === 'email'" class="login-form" @submit.prevent="requestCode">
          <label>
            Email
            <input v-model="email" type="email" autocomplete="username" required />
          </label>
          <button type="submit" class="primary" :disabled="submitting">
            {{ submitting ? 'Sending…' : 'Send code' }}
          </button>
        </form>

        <form v-else class="login-form" @submit.prevent="verifyCode">
          <p class="login-hint">A 6-digit code was sent to {{ email }}.</p>
          <p v-if="devCode" class="login-dev-code">Dev code: {{ devCode }}</p>
          <label>
            Code
            <input v-model="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" required />
          </label>
          <button type="submit" class="primary" :disabled="submitting">
            {{ submitting ? 'Verifying…' : 'Verify and sign in' }}
          </button>
          <button type="button" class="link-button" @click="step = 'email'">Use another email</button>
        </form>

        <button v-if="showDevSignIn" type="button" class="link-button dev-link" @click="devSignIn">
          Development sign-in
        </button>
      </template>

      <template v-else>
        <h1 id="login-title">Customer sign-in</h1>
        <p class="login-hint">Customers sign in on the customer portal to submit and track tasks.</p>
        <a class="primary-link" :href="customerPortalUrl">Go to customer portal</a>
      </template>

      <p v-if="error" class="login-error" role="alert">{{ error }}</p>
    </section>
  </div>
</template>
