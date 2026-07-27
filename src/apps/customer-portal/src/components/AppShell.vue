<script setup>
import { computed } from 'vue';
import { RouterLink, RouterView } from 'vue-router';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import SkipToContent from './SkipToContent.vue';
import WorkspaceSwitcher from './WorkspaceSwitcher.vue';

const navItems = [
  { to: '/', labelKey: 'nav.dashboard', permission: null },
  { to: '/tasks', labelKey: 'nav.tasks', permission: 'customer.tasks:read' },
  { to: '/files', labelKey: 'nav.files', permission: 'customer.tasks:read' },
  { to: '/webhooks', labelKey: 'nav.webhooks', permission: 'customer.webhooks:read' },
  { to: '/api-keys', labelKey: 'nav.apiKeys', permission: 'customer.apikeys:read' },
  { to: '/billing', labelKey: 'nav.billing', permission: 'customer.billing:read' },
  { to: '/disputes', labelKey: 'nav.disputes', permission: 'customer.billing:read' },
  { to: '/team', labelKey: 'nav.team', permission: 'customer.team:read' },
  { to: '/settings', labelKey: 'nav.settings', permission: null },
];

const session = useSession();

const visibleNavItems = computed(() =>
  navItems.filter((item) => item.permission === null || session.hasPermission(item.permission)),
);
</script>

<template>
  <RouterView v-if="!session.authenticated" />
  <template v-else>
    <SkipToContent />
    <header class="topbar">
      <div class="brand">
        <strong>EdgeMint</strong>
        <span class="badge">{{ t('app.title') }}</span>
      </div>
      <WorkspaceSwitcher />
      <button type="button" class="secondary-button" @click="session.logout()">Sign out</button>
    </header>
    <div class="layout">
      <nav aria-label="Primary">
        <ul class="nav-list">
          <li v-for="item in visibleNavItems" :key="item.to">
            <RouterLink :to="item.to" exact-active-class="active">{{ t(item.labelKey) }}</RouterLink>
          </li>
        </ul>
      </nav>
      <main id="main-content" tabindex="-1">
        <RouterView />
      </main>
    </div>
  </template>
</template>
