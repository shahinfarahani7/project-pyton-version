<script setup>
import { computed } from 'vue';
import { RouterLink, RouterView, useRouter } from 'vue-router';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import SkipToContent from './SkipToContent.vue';
import WorkspaceSwitcher from './WorkspaceSwitcher.vue';

const navItems = [
  { name: 'dashboard', labelKey: 'nav.dashboard', icon: 'dashboard', permission: null },
  { name: 'tasks', labelKey: 'nav.tasks', icon: 'assignment', permission: 'customer.tasks:read' },
  { name: 'files', labelKey: 'nav.files', icon: 'folder_open', permission: 'customer.tasks:read' },
  { name: 'webhooks', labelKey: 'nav.webhooks', icon: 'webhook', permission: 'customer.webhooks:read' },
  { name: 'api-keys', labelKey: 'nav.apiKeys', icon: 'key', permission: 'customer.apikeys:read' },
  { name: 'billing', labelKey: 'nav.billing', icon: 'payments', permission: 'customer.billing:read' },
  { name: 'disputes', labelKey: 'nav.disputes', icon: 'gavel', permission: 'customer.billing:read' },
  { name: 'team', labelKey: 'nav.team', icon: 'groups', permission: 'customer.team:read' },
  { name: 'settings', labelKey: 'nav.settings', icon: 'settings', permission: null },
];

const session = useSession();
const router = useRouter();

const visibleNavItems = computed(() =>
  navItems.filter((item) => item.permission === null || session.hasPermission(item.permission)),
);

const activeWorkspace = computed(() =>
  session.workspaces.find((workspace) => workspace.id === session.workspaceId),
);

async function signOut() {
  await session.logout();
  await router.push({ name: 'login' });
}
</script>

<template>
  <div class="md-app">
    <SkipToContent />
    <nav class="md-nav-drawer" aria-label="Primary">
      <div class="md-brand">
        <div class="md-brand__logo" aria-hidden="true">
          <span class="material-symbols-outlined">hub</span>
        </div>
        <div>
          <p class="md-brand__title">EdgeMint</p>
          <p class="md-brand__subtitle">{{ t('app.title') }}</p>
        </div>
      </div>
      <ul class="md-nav-list">
        <li v-for="item in visibleNavItems" :key="item.name">
          <RouterLink :to="{ name: item.name }" class="md-nav-link" active-class="active">
            <span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span>
            {{ t(item.labelKey) }}
          </RouterLink>
        </li>
      </ul>
    </nav>
    <div class="md-app-main">
      <header class="md-top-app-bar">
        <div>
          <strong>{{ activeWorkspace?.name ?? t('workspace.unknown') }}</strong>
          <p class="page-subtitle">{{ activeWorkspace?.environment ?? '—' }}</p>
        </div>
        <div class="md-top-app-bar__actions">
          <WorkspaceSwitcher />
          <button type="button" class="md-btn md-btn-text" @click="signOut()">
            <span class="material-symbols-outlined" aria-hidden="true">logout</span>
            {{ t('auth.signOut') }}
          </button>
        </div>
      </header>
      <main id="main-content" class="md-content" tabindex="-1">
        <RouterView />
      </main>
    </div>
  </div>
</template>
