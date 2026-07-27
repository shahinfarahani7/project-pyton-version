<script setup>
import { useSession } from '../auth/session';
import { t } from '../i18n';

const session = useSession();
</script>

<template>
  <section class="panel">
    <h1>{{ t('nav.dashboard') }}</h1>
    <p>Authenticated BFF session with opaque cookie. Provider tokens never reach browser JavaScript.</p>
    <dl class="meta-grid">
      <div>
        <dt>Session</dt>
        <dd>{{ session.sessionPublicId }}</dd>
      </div>
      <div>
        <dt>Workspace</dt>
        <dd>{{ session.workspaceId }}</dd>
      </div>
      <div>
        <dt>Authorization generation</dt>
        <dd>{{ session.authorizationGeneration }}</dd>
      </div>
    </dl>
  </section>
</template>
