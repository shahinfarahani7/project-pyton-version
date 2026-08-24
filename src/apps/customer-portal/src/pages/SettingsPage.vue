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
      <PageHeader :title="t('settings.sessionTitle')" />
      <dl class="stat-grid">
        <div>
          <dt class="stat-card__label">{{ t('dashboard.sessionId') }}</dt>
          <dd>{{ session.sessionPublicId ?? '—' }}</dd>
        </div>
        <div>
          <dt class="stat-card__label">{{ t('dashboard.workspaceId') }}</dt>
          <dd>{{ session.workspaceId ?? '—' }}</dd>
        </div>
        <div>
          <dt class="stat-card__label">{{ t('settings.permissions') }}</dt>
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
