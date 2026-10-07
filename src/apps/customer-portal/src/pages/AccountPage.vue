<script setup>
import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import StatusChip from '../components/ui/StatusChip.vue';
import { useAsyncResource } from '../composables/useAsyncResource';
import { t } from '../i18n';

const session = useSession();

const { data: profile, loading } = useAsyncResource(() => portalApi.currentPrincipal(), {
  enabled: () => session.authenticated,
});
</script>

<template>
  <section class="em-page">
    <article class="md-card">
      <h2 class="em-section-title">{{ t('account.session') }}</h2>
      <div v-if="loading" class="md-skeleton" style="height: 4rem" />
      <dl v-else class="em-kv-list">
        <div>
          <dt>{{ t('account.name') }}</dt>
          <dd>{{ profile?.displayName || '—' }}</dd>
        </div>
        <div>
          <dt>{{ t('account.email') }}</dt>
          <dd>{{ profile?.email || '—' }}</dd>
        </div>
        <div>
          <dt>{{ t('dashboard.sessionId') }}</dt>
          <dd><code>{{ session.sessionPublicId ?? '—' }}</code></dd>
        </div>
        <div>
          <dt>{{ t('dashboard.workspaceId') }}</dt>
          <dd><code>{{ session.workspaceId ?? '—' }}</code></dd>
        </div>
      </dl>
    </article>

    <article class="md-card">
      <h2 class="em-section-title">{{ t('account.permissions') }}</h2>
      <div class="permission-list">
        <StatusChip v-for="permission in session.permissions" :key="permission" :status="permission" />
      </div>
    </article>
  </section>
</template>
