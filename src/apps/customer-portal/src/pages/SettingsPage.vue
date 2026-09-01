<script setup>
import { useSession } from '../auth/session';
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';

const session = useSession();
</script>

<template>
  <section class="em-page">
    <PageHeader :title="t('nav.settings')" :subtitle="t('settings.subtitle')" />

    <article class="md-card">
      <p class="stat-card__label">{{ t('settings.telemetry') }}</p>
      <p>{{ t('settings.telemetryHint') }}</p>
    </article>

    <article class="md-card">
      <header class="em-section-header">
        <h2 class="em-section-title">{{ t('settings.sessionTitle') }}</h2>
      </header>
      <dl class="em-kv-list">
        <div>
          <dt>{{ t('dashboard.sessionId') }}</dt>
          <dd><code>{{ session.sessionPublicId ?? '—' }}</code></dd>
        </div>
        <div>
          <dt>{{ t('dashboard.workspaceId') }}</dt>
          <dd><code>{{ session.workspaceId ?? '—' }}</code></dd>
        </div>
        <div>
          <dt>{{ t('settings.permissions') }}</dt>
          <dd class="permission-list">
            <StatusChip v-for="permission in session.permissions" :key="permission" :status="permission" />
          </dd>
        </div>
      </dl>
    </article>

    <article class="md-card">
      <PageHeader :title="t('settings.securityTitle')" :subtitle="t('settings.securitySubtitle')" />
    </article>
  </section>
</template>
