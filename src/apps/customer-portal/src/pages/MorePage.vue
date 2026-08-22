<script setup>
import { RouterLink } from 'vue-router';

import { useSession } from '../auth/session';
import { t } from '../i18n';

const session = useSession();

const menuSections = [
  {
    titleKey: 'more.integrations',
    items: [
      { name: 'api-keys', labelKey: 'nav.apiKeys', icon: 'key', permission: 'customer.apikeys:read' },
      { name: 'webhooks', labelKey: 'nav.webhooks', icon: 'webhook', permission: 'customer.webhooks:read' },
    ],
  },
  {
    titleKey: 'more.workspace',
    items: [
      { name: 'files', labelKey: 'nav.files', icon: 'folder_open', permission: 'customer.tasks:read' },
      { name: 'team', labelKey: 'nav.team', icon: 'groups', permission: 'customer.team:read' },
      { name: 'disputes', labelKey: 'nav.disputes', icon: 'gavel', permission: 'customer.billing:read' },
      { name: 'settings', labelKey: 'nav.settings', icon: 'settings', permission: null },
    ],
  },
];

const visibleSections = menuSections
  .map((section) => ({
    ...section,
    items: section.items.filter(
      (item) => item.permission === null || session.hasPermission(item.permission),
    ),
  }))
  .filter((section) => section.items.length);
</script>

<template>
  <section class="em-page">
    <article class="md-card em-sla-card">
      <div class="em-sla-card__header">
        <span class="em-status-pill em-status-pill--success">
          <span class="material-symbols-outlined" aria-hidden="true">check_circle</span>
          {{ t('more.systemsOperational') }}
        </span>
      </div>
      <div class="em-sla-metrics">
        <div><span>{{ t('more.slaUptime') }}</span><strong>100.0%</strong></div>
        <div><span>{{ t('more.fallbackRate') }}</span><strong>0.15%</strong></div>
        <div><span>{{ t('more.cloudFallback') }}</span><strong>12</strong></div>
      </div>
    </article>

    <section v-for="section in visibleSections" :key="section.titleKey" class="em-more-section">
      <h2 class="em-section-title">{{ t(section.titleKey) }}</h2>
      <ul class="em-more-list">
        <li v-for="item in section.items" :key="item.name">
          <RouterLink :to="{ name: item.name }" class="em-more-link">
            <span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span>
            <span>{{ t(item.labelKey) }}</span>
            <span class="material-symbols-outlined em-more-link__chevron" aria-hidden="true">chevron_right</span>
          </RouterLink>
        </li>
      </ul>
    </section>
  </section>
</template>
