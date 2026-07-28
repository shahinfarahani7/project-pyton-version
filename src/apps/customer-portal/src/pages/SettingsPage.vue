<script setup>
import { ref } from 'vue';

import { useSession } from '../auth/session';
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { resolveLocale, t } from '../i18n';

const session = useSession();
const locale = ref(resolveLocale());

function onLocaleChange(event) {
  locale.value = event.target.value;
  document.documentElement.lang = locale.value === 'fa' ? 'fa' : 'en';
}
</script>

<template>
  <section>
    <PageHeader :title="t('nav.settings')" :subtitle="t('settings.subtitle')" />

    <article class="md-card grid-2">
      <div class="md-field">
        <label for="locale-select">{{ t('settings.locale') }}</label>
        <select id="locale-select" class="md-select" :value="locale" @change="onLocaleChange">
          <option value="en">English</option>
          <option value="fa">فارسی</option>
        </select>
        <p class="login-note">{{ t('settings.localeHint') }}</p>
      </div>
      <div>
        <p class="stat-card__label">{{ t('settings.telemetry') }}</p>
        <p>{{ t('settings.telemetryHint') }}</p>
      </div>
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
