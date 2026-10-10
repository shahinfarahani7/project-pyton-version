<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';

import { authApi } from '../api/client';
import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

const session = useSession();
const router = useRouter();

const email = ref('dev-user@edgemint.local');
const password = ref('');
const code = ref('');
const challengeId = ref('');
const devCode = ref('');
const method = ref('password');
const mode = ref('signin');
const step = ref('email');
const error = ref('');
const submitting = ref(false);
const showPassword = ref(false);
const confirmPassword = ref('');

function redirectTarget() {
  const redirect = router.currentRoute.value.query.redirect;
  return typeof redirect === 'string' ? redirect : { name: 'dashboard' };
}

async function requestCode() {
  error.value = '';
  const value = email.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
    error.value = t('login.invalidEmail');
    return;
  }
  submitting.value = true;
  try {
    const issued = await authApi.requestEmailOtp(value);
    challengeId.value = issued.challengeId;
    devCode.value = typeof issued.devCode === 'string' ? issued.devCode : '';
    code.value = '';
    step.value = 'otp';
    trackEvent('portal.login.otp.requested');
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('login.requestFailed');
  } finally {
    submitting.value = false;
  }
}

async function verifyCode() {
  error.value = '';
  const value = code.value.trim();
  if (!/^\d{6}$/.test(value)) {
    error.value = t('login.invalidCode');
    return;
  }
  submitting.value = true;
  try {
    trackEvent('portal.login.otp.verify');
    await session.loginWithEmailOtp({
      email: email.value.trim(),
      challengeId: challengeId.value,
      code: value,
    });
    await router.replace(redirectTarget());
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('login.verifyFailed');
  } finally {
    submitting.value = false;
  }
}

function changeEmail() {
  step.value = 'email';
  code.value = '';
  devCode.value = '';
  challengeId.value = '';
  error.value = '';
}

function selectMethod(next) {
  method.value = next;
  error.value = '';
}

function showSignUp() {
  mode.value = 'signup';
  error.value = '';
  password.value = '';
  confirmPassword.value = '';
  showPassword.value = false;
  if (email.value.trim().toLowerCase() === 'dev-user@edgemint.local') {
    email.value = '';
  }
}

function showSignIn() {
  mode.value = 'signin';
  error.value = '';
  password.value = '';
  confirmPassword.value = '';
  showPassword.value = false;
  if (!email.value.trim()) {
    email.value = 'dev-user@edgemint.local';
  }
}

async function signUp() {
  error.value = '';
  const address = email.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) {
    error.value = t('login.invalidEmail');
    return;
  }
  if (password.value.length < 8) {
    error.value = t('login.shortPassword');
    return;
  }
  if (password.value !== confirmPassword.value) {
    error.value = t('login.passwordMismatch');
    return;
  }
  submitting.value = true;
  try {
    trackEvent('portal.signup.password');
    await session.signUpWithPassword({ email: address, password: password.value });
    await router.replace(redirectTarget());
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('login.signupFailed');
  } finally {
    submitting.value = false;
  }
}

async function signInWithPassword() {
  error.value = '';
  const address = email.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) {
    error.value = t('login.invalidEmail');
    return;
  }
  if (!password.value) {
    error.value = t('login.invalidPassword');
    return;
  }
  submitting.value = true;
  try {
    trackEvent('portal.login.password');
    await session.loginWithPassword({ email: address, password: password.value });
    await router.replace(redirectTarget());
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('login.verifyFailed');
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div class="login-scene">
    <div class="login-layout">
      <section class="login-hero">
        <div class="login-brand">
          <span class="login-brand__mark" aria-hidden="true">
            <span class="material-symbols-outlined">hub</span>
          </span>
          <span class="login-brand__name">EdgeMint</span>
        </div>
        <div class="login-hero__copy">
          <h1>{{ t('login.heroTitle') }}</h1>
          <p>{{ t('login.heroBody') }}</p>
        </div>
        <ul class="login-points">
          <li>
            <span class="material-symbols-outlined" aria-hidden="true">shield_lock</span>
            {{ t('login.pointSession') }}
          </li>
          <li>
            <span class="material-symbols-outlined" aria-hidden="true">domain</span>
            {{ t('login.pointWorkspace') }}
          </li>
          <li>
            <span class="material-symbols-outlined" aria-hidden="true">fact_check</span>
            {{ t('login.pointAudit') }}
          </li>
        </ul>
      </section>
      <section class="md-card login-panel">
        <header class="login-panel__header">
          <h2 class="page-title">{{ mode === 'signup' ? t('login.signupTitle') : t('login.title') }}</h2>
          <p class="login-note">{{ mode === 'signup' ? t('login.signupNote') : t('login.note') }}</p>
        </header>
        <div v-if="mode === 'signin'" class="login-methods" role="group" :aria-label="t('login.methodLabel')">
          <button
            type="button"
            class="login-method"
            :class="{ 'login-method--active': method === 'password' }"
            :aria-pressed="method === 'password'"
            data-testid="login-method-password"
            @click="selectMethod('password')"
          >
            {{ t('login.methodPassword') }}
          </button>
          <button
            type="button"
            class="login-method"
            :class="{ 'login-method--active': method === 'otp' }"
            :aria-pressed="method === 'otp'"
            data-testid="login-method-otp"
            @click="selectMethod('otp')"
          >
            {{ t('login.methodOtp') }}
          </button>
        </div>
        <form
          v-if="mode === 'signup'"
          class="login-form"
          data-testid="login-signup-form"
          @submit.prevent="signUp"
        >
          <label class="md-field">
            {{ t('login.email') }}
            <input
              v-model="email"
              class="md-input"
              type="email"
              name="email"
              autocomplete="username"
              required
              data-testid="login-email"
            />
          </label>
          <label class="md-field">
            {{ t('login.password') }}
            <span class="login-field-control">
              <input
                v-model="password"
                class="md-input"
                :type="showPassword ? 'text' : 'password'"
                name="new-password"
                autocomplete="new-password"
                minlength="8"
                required
                data-testid="login-password"
              />
              <button
                type="button"
                class="login-field-toggle"
                :aria-label="showPassword ? t('login.hidePassword') : t('login.showPassword')"
                :aria-pressed="showPassword"
                @click="showPassword = !showPassword"
              >
                <span class="material-symbols-outlined" aria-hidden="true">{{ showPassword ? 'visibility_off' : 'visibility' }}</span>
              </button>
            </span>
            <ul class="login-password-rules" data-testid="login-password-rules">
              <li :class="{ 'is-met': password.length >= 8 }">{{ t('login.ruleLength') }}</li>
            </ul>
          </label>
          <label class="md-field">
            {{ t('login.confirmPassword') }}
            <input
              v-model="confirmPassword"
              class="md-input"
              :type="showPassword ? 'text' : 'password'"
              name="confirm-password"
              autocomplete="new-password"
              minlength="8"
              required
              data-testid="login-confirm-password"
            />
            <ul class="login-password-rules" data-testid="login-confirm-rules">
              <li :class="{ 'is-met': confirmPassword.length > 0 && confirmPassword === password }">
                {{ t('login.ruleMatch') }}
              </li>
            </ul>
          </label>
          <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
          <button type="submit" class="md-btn md-btn-filled" data-testid="login-signup-submit" :disabled="submitting">
            {{ t('login.createAccount') }}
          </button>
          <div class="login-form__links">
            <button type="button" class="md-btn md-btn-text" data-testid="login-show-signin" @click="showSignIn">
              {{ t('login.haveAccount') }}
            </button>
          </div>
        </form>
        <form
          v-else-if="method === 'password'"
          class="login-form"
          data-testid="login-password-form"
          @submit.prevent="signInWithPassword"
        >
          <label class="md-field">
            {{ t('login.email') }}
            <input
              v-model="email"
              class="md-input"
              type="email"
              name="email"
              autocomplete="username"
              required
              data-testid="login-email"
            />
          </label>
          <label class="md-field">
            {{ t('login.password') }}
            <span class="login-field-control">
              <input
                v-model="password"
                class="md-input"
                :type="showPassword ? 'text' : 'password'"
                name="password"
                autocomplete="current-password"
                required
                data-testid="login-password"
              />
              <button
                type="button"
                class="login-field-toggle"
                :aria-label="showPassword ? t('login.hidePassword') : t('login.showPassword')"
                :aria-pressed="showPassword"
                @click="showPassword = !showPassword"
              >
                <span class="material-symbols-outlined" aria-hidden="true">{{ showPassword ? 'visibility_off' : 'visibility' }}</span>
              </button>
            </span>
          </label>
          <p class="login-dev-code" data-testid="login-dev-password">
            {{ t('login.devPassword') }}
          </p>
          <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
          <button type="submit" class="md-btn md-btn-filled" data-testid="login-password-submit" :disabled="submitting">
            {{ t('login.verify') }}
          </button>
        </form>
        <form
          v-else-if="step === 'email'"
          class="login-form"
          data-testid="login-email-form"
          @submit.prevent="requestCode"
        >
          <label class="md-field">
            {{ t('login.email') }}
            <input
              v-model="email"
              class="md-input"
              type="email"
              name="email"
              autocomplete="username"
              required
              data-testid="login-email"
            />
          </label>
          <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
          <button type="submit" class="md-btn md-btn-filled" data-testid="login-request-code" :disabled="submitting">
            {{ t('login.requestCode') }}
          </button>
        </form>
        <form
          v-else
          class="login-form"
          data-testid="login-otp-form"
          @submit.prevent="verifyCode"
        >
          <p class="login-note">{{ t('login.otpSent', { email }) }}</p>
          <p v-if="devCode" class="login-dev-code" data-testid="login-dev-code">
            {{ t('login.devCode', { code: devCode }) }}
          </p>
          <label class="md-field">
            {{ t('login.otp') }}
            <input
              v-model="code"
              class="md-input login-otp"
              type="text"
              name="one-time-code"
              inputmode="numeric"
              autocomplete="one-time-code"
              maxlength="6"
              pattern="\d{6}"
              required
              data-testid="login-otp"
            />
          </label>
          <p v-if="error" class="md-alert md-alert--error" role="alert">{{ error }}</p>
          <button type="submit" class="md-btn md-btn-filled" data-testid="login-verify" :disabled="submitting">
            {{ t('login.verify') }}
          </button>
          <div class="login-form__links">
            <button type="button" class="md-btn md-btn-text" data-testid="login-resend" :disabled="submitting" @click="requestCode">
              {{ t('login.resend') }}
            </button>
            <button type="button" class="md-btn md-btn-text" @click="changeEmail">
              {{ t('login.changeEmail') }}
            </button>
          </div>
        </form>
        <div v-if="mode === 'signin' && (method === 'password' || step === 'email')" class="login-form__links">
          <button type="button" class="md-btn md-btn-text" data-testid="login-show-signup" @click="showSignUp">
            {{ t('login.createAccount') }}
          </button>
        </div>
      </section>
    </div>
  </div>
</template>
