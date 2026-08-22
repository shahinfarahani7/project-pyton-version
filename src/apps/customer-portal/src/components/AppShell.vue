<script setup>
import { computed, ref } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';

import { useSession } from '../auth/session';
import { t } from '../i18n';
import SkipToContent from './SkipToContent.vue';
import WorkspaceSwitcher from './WorkspaceSwitcher.vue';

const bottomNavItems = [
  { name: 'dashboard', labelKey: 'nav.dashboard', icon: 'home' },
  { name: 'tasks', labelKey: 'nav.tasks', icon: 'assignment' },
  { name: 'usage', labelKey: 'nav.usage', icon: 'bar_chart' },
  { name: 'billing', labelKey: 'nav.billing', icon: 'account_balance_wallet' },
  { name: 'more', labelKey: 'nav.more', icon: 'more_horiz' },
];

const sidebarItems = [
  { name: 'dashboard', labelKey: 'nav.dashboard', icon: 'home', permission: null },
  { name: 'tasks', labelKey: 'nav.tasks', icon: 'assignment', permission: 'customer.tasks:read' },
  { name: 'usage', labelKey: 'nav.usage', icon: 'bar_chart', permission: 'customer.billing:read' },
  { name: 'billing', labelKey: 'nav.billing', icon: 'payments', permission: 'customer.billing:read' },
  { name: 'api-keys', labelKey: 'nav.apiKeys', icon: 'key', permission: 'customer.apikeys:read' },
  { name: 'webhooks', labelKey: 'nav.webhooks', icon: 'webhook', permission: 'customer.webhooks:read' },
  { name: 'files', labelKey: 'nav.files', icon: 'folder_open', permission: 'customer.tasks:read' },
  { name: 'team', labelKey: 'nav.team', icon: 'groups', permission: 'customer.team:read' },
  { name: 'disputes', labelKey: 'nav.disputes', icon: 'gavel', permission: 'customer.billing:read' },
  { name: 'settings', labelKey: 'nav.settings', icon: 'settings', permission: null },
];

const session = useSession();
const router = useRouter();
const route = useRoute();
const drawerOpen = ref(false);

const visibleBottomNav = computed(() => bottomNavItems);

const visibleSidebarItems = computed(() =>
  sidebarItems.filter((item) => item.permission === null || session.hasPermission(item.permission)),
);

const activeWorkspace = computed(() =>
  session.workspaces.find((workspace) => workspace.id === session.workspaceId),
);

const avatarLetter = computed(() =>
  (activeWorkspace.value?.name ?? 'E').charAt(0).toUpperCase(),
);

const pageTitle = computed(() => {
  const metaTitle = route.meta?.titleKey;
  return metaTitle ? t(metaTitle) : t('app.title');
});

const hideBottomNav = computed(() => Boolean(route.meta?.hideBottomNav));

function isNavActive(itemName) {
  if (itemName === 'tasks') {
    return route.name === 'tasks' || String(route.name).startsWith('task');
  }
  return route.name === itemName;
}

function openDrawer() {
  drawerOpen.value = true;
}

function closeDrawer() {
  drawerOpen.value = false;
}

function onNavigate() {
  closeDrawer();
}

async function signOut() {
  closeDrawer();
  await session.logout();
  await router.push({ name: 'login' });
}
</script>

<template>
  <div class="em-app">
    <SkipToContent />

    <aside class="em-sidebar" aria-label="Primary">
      <div class="em-sidebar__brand md-brand">
        <div class="md-brand__logo" aria-hidden="true">
          <span class="material-symbols-outlined">hub</span>
        </div>
        <div>
          <p class="md-brand__title">EdgeMint AI</p>
          <p class="md-brand__subtitle">{{ t('app.title') }}</p>
        </div>
      </div>

      <WorkspaceSwitcher class="em-sidebar__workspace" />

      <ul class="em-sidebar__list">
        <li v-for="item in visibleSidebarItems" :key="item.name">
          <RouterLink
            :to="{ name: item.name }"
            class="em-sidebar__link"
            :class="{ active: isNavActive(item.name) }"
          >
            <span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span>
            {{ t(item.labelKey) }}
          </RouterLink>
        </li>
      </ul>

      <button type="button" class="md-btn md-btn-outlined em-sidebar__signout" @click="signOut">
        <span class="material-symbols-outlined" aria-hidden="true">logout</span>
        {{ t('auth.signOut') }}
      </button>
    </aside>

    <div class="em-app-frame">
      <header v-if="!route.meta?.hideShellHeader" class="em-top-bar">
        <button
          type="button"
          class="em-icon-btn em-top-bar__menu"
          aria-label="Menu"
          @click="openDrawer"
        >
          <span class="material-symbols-outlined" aria-hidden="true">menu</span>
        </button>
        <div class="em-top-bar__brand">
          <span class="em-top-bar__logo em-top-bar__logo--mobile" aria-hidden="true">
            <span class="material-symbols-outlined">hub</span>
          </span>
          <div>
            <strong>{{ pageTitle }}</strong>
            <p class="em-top-bar__env">
              {{ activeWorkspace?.name ?? t('workspace.unknown') }}
              ·
              {{ activeWorkspace?.environment ?? '—' }}
            </p>
          </div>
        </div>
        <div class="em-top-bar__actions">
          <WorkspaceSwitcher class="em-top-bar__workspace" />
          <div class="avatar em-top-bar__avatar" aria-hidden="true">{{ avatarLetter }}</div>
        </div>
      </header>

      <main
        id="main-content"
        class="em-content"
        :class="{ 'em-content--no-nav': hideBottomNav }"
        tabindex="-1"
      >
        <RouterView @open-menu="openDrawer" />
      </main>

      <nav
        v-if="!hideBottomNav"
        class="em-bottom-nav"
        :style="{ '--em-bottom-nav-columns': visibleBottomNav.length }"
        aria-label="Primary"
      >
        <RouterLink
          v-for="item in visibleBottomNav"
          :key="item.name"
          :to="{ name: item.name }"
          class="em-bottom-nav__item"
          :class="{ active: isNavActive(item.name) }"
        >
          <span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span>
          <span>{{ t(item.labelKey) }}</span>
        </RouterLink>
      </nav>
    </div>

    <nav class="em-drawer" :class="{ 'em-drawer--open': drawerOpen }" aria-label="Menu">
      <div class="em-drawer__backdrop" @click="closeDrawer" />
      <aside class="em-drawer__panel">
        <div class="em-drawer__header">
          <div class="md-brand">
            <div class="md-brand__logo" aria-hidden="true">
              <span class="material-symbols-outlined">hub</span>
            </div>
            <div>
              <p class="md-brand__title">EdgeMint AI</p>
              <p class="md-brand__subtitle">{{ t('app.title') }}</p>
            </div>
          </div>
          <button type="button" class="em-icon-btn" aria-label="Close menu" @click="closeDrawer">
            <span class="material-symbols-outlined" aria-hidden="true">close</span>
          </button>
        </div>
        <WorkspaceSwitcher class="em-drawer__workspace" />
        <ul class="em-drawer__list">
          <li v-for="item in visibleSidebarItems" :key="item.name">
            <RouterLink :to="{ name: item.name }" class="em-drawer__link" @click="onNavigate">
              <span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span>
              {{ t(item.labelKey) }}
            </RouterLink>
          </li>
        </ul>
        <button type="button" class="md-btn md-btn-outlined em-drawer__signout" @click="signOut">
          <span class="material-symbols-outlined" aria-hidden="true">logout</span>
          {{ t('auth.signOut') }}
        </button>
      </aside>
    </nav>
  </div>
</template>
