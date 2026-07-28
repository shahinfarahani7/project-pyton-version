<script setup>
import { useRouter } from 'vue-router';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

const session = useSession();
const router = useRouter();

async function signInDev() {
  trackEvent('portal.login.dev');
  await session.loginDev('00000000-0000-0000-0000-00000000000b');
  const redirect = typeof router.currentRoute.value.query.redirect === 'string'
    ? router.currentRoute.value.query.redirect
    : null;
  await router.replace(redirect ?? { name: 'dashboard' });
}

function signInWithOidc() {
  trackEvent('portal.login.oidc');
  session.loginWithOidc();
}
</script>

<template>
  <div class="login-scene">
    <div class="login-layout">
      <section class="login-hero">
        <h1>{{ t('login.heroTitle') }}</h1>
        <p>{{ t('login.heroBody') }}</p>
      </section>
      <section class="md-card login-panel">
        <h2 class="page-title">{{ t('login.title') }}</h2>
        <p class="login-note">
          OIDC Authorization Code with PKCE completes on the server. Only the opaque BFF cookie is stored in the
          browser.
        </p>
        <div class="login-actions">
          <button type="button" class="md-btn md-btn-filled" @click="signInWithOidc">
            <span class="material-symbols-outlined" aria-hidden="true">login</span>
            {{ t('login.oidc') }}
          </button>
          <button
            type="button"
            class="md-btn md-btn-tonal secondary-button"
            data-testid="dev-sign-in"
            @click="signInDev()"
          >
            <span class="material-symbols-outlined" aria-hidden="true">developer_mode</span>
            {{ t('login.dev') }}
          </button>
        </div>
      </section>
    </div>
  </div>
</template>
