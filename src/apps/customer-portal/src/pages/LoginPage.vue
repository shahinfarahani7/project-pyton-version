<script setup>
import { watch } from 'vue';
import { useRouter } from 'vue-router';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

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

function signInWithOidc() {
  trackEvent('portal.login.oidc');
  session.loginWithOidc();
}

function signInDev() {
  trackEvent('portal.login.dev');
  void session.loginDev('00000000-0000-0000-0000-00000000000b');
}
</script>

<template>
  <section v-if="!session.authenticated" class="panel login-panel">
    <h1>{{ t('login.title') }}</h1>
    <p>
      OIDC Authorization Code with PKCE completes on the server. Only the opaque BFF cookie is stored in the
      browser.
    </p>
    <div class="login-actions">
      <button type="button" class="primary-button" @click="signInWithOidc">{{ t('login.oidc') }}</button>
      <button type="button" class="secondary-button" @click="signInDev">{{ t('login.dev') }}</button>
    </div>
  </section>
</template>
