<script setup>
import { computed } from 'vue';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import StatusChip from '../components/ui/StatusChip.vue';
import { useAsyncResource } from '../composables/useAsyncResource';
import { t } from '../i18n';

const session = useSession();

const { data: profile, loading } = useAsyncResource(() => portalApi.currentPrincipal(), {
  enabled: () => session.authenticated,
});

const initials = computed(() => {
  const parts = String(profile.value?.displayName || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (!parts.length) {
    return 'FN';
  }
  return parts
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase();
});
</script>

<template>
  <section class="em-page fn-split">
    <article class="md-card">
      <h2 class="em-section-title">{{ t('account.session') }}</h2>
      <div v-if="loading" class="md-skeleton" style="height: 4rem" />
      <template v-else>
        <div class="fn-profile">
          <span class="fn-avatar fn-avatar--large" aria-hidden="true">{{ initials }}</span>
          <div>
            <h2>{{ profile?.displayName || '—' }}</h2>
            <p class="fn-sub">{{ profile?.email || '—' }}</p>
          </div>
        </div>
        <dl class="em-kv-list">
          <div>
            <dt>{{ t('account.name') }}</dt>
            <dd>{{ profile?.displayName || '—' }}</dd>
          </div>
          <div>
            <dt>{{ t('account.email') }}</dt>
            <dd>{{ profile?.email || '—' }}</dd>
          </div>
        </dl>
        <details class="fn-details">
          <summary>{{ t('dashboard.sessionTitle') }}</summary>
          <dl class="em-kv-list">
            <div>
              <dt>{{ t('dashboard.sessionId') }}</dt>
              <dd><code>{{ session.sessionPublicId ?? '—' }}</code></dd>
            </div>
            <div>
              <dt>{{ t('dashboard.workspaceId') }}</dt>
              <dd><code>{{ session.workspaceId ?? '—' }}</code></dd>
            </div>
          </dl>
        </details>
      </template>
    </article>

    <article class="md-card">
      <h2 class="em-section-title">{{ t('account.permissions') }}</h2>
      <div class="permission-list">
        <StatusChip v-for="permission in session.permissions" :key="permission" :status="permission" />
      </div>
    </article>
  </section>
</template>
