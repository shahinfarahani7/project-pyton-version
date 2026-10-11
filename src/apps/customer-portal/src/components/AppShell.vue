<script setup>
import { computed, onMounted, ref } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';

import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { t } from '../i18n';
import BrandLockup from './BrandLockup.vue';
import SkipToContent from './SkipToContent.vue';
import StrokeIcon from './ui/StrokeIcon.vue';

const bottomNavItems = [
  { name: 'dashboard', labelKey: 'nav.dashboard', icon: 'grid' },
  { name: 'tasks', labelKey: 'nav.tasks', icon: 'spark' },
  { name: 'usage', labelKey: 'nav.usage', icon: 'chart' },
  { name: 'billing', labelKey: 'nav.billing', icon: 'wallet' },
  { name: 'more', labelKey: 'nav.more', icon: 'more' },
];

const navGroups = [
  {
    labelKey: 'nav.groupWorkspace',
    items: [
      { name: 'dashboard', labelKey: 'nav.dashboard', icon: 'grid', permission: null },
      { name: 'tasks', labelKey: 'nav.tasks', icon: 'spark', permission: 'customer.tasks:read' },
      { name: 'usage', labelKey: 'nav.usage', icon: 'chart', permission: 'customer.billing:read' },
    ],
  },
  {
    labelKey: 'nav.groupFinance',
    items: [
      { name: 'billing', labelKey: 'nav.billing', icon: 'wallet', permission: 'customer.billing:read' },
      { name: 'wallet', labelKey: 'nav.wallet', icon: 'wallet', permission: 'customer.billing:read' },
    ],
  },
  {
    labelKey: 'nav.groupBuild',
    items: [
      { name: 'api-keys', labelKey: 'nav.apiKeys', icon: 'key', permission: 'customer.apikeys:read' },
      { name: 'files', labelKey: 'nav.files', icon: 'file', permission: 'customer.tasks:read' },
    ],
  },
  {
    labelKey: 'nav.groupPersonal',
    items: [
      { name: 'account', labelKey: 'nav.account', icon: 'team', permission: null },
    ],
  },
];

const pageSubtitles = {
  dashboard: 'shell.overviewSubtitle',
  tasks: 'shell.tasksSubtitle',
  usage: 'shell.usageSubtitle',
  billing: 'shell.billingSubtitle',
  wallet: 'shell.walletSubtitle',
  'api-keys': 'shell.keysSubtitle',
  files: 'shell.filesSubtitle',
  account: 'shell.accountSubtitle',
  more: 'shell.moreSubtitle',
  'task-detail': 'shell.detailSubtitle',
};

const session = useSession();
const router = useRouter();
const route = useRoute();
const drawerOpen = ref(false);
const profile = ref(null);

const visibleBottomNav = computed(() => bottomNavItems);

const visibleNavGroups = computed(() =>
  navGroups
    .map((group) => ({
      ...group,
      items: group.items.filter((item) => item.permission === null || session.hasPermission(item.permission)),
    }))
    .filter((group) => group.items.length),
);

const pageTitle = computed(() => {
  const metaTitle = route.meta?.titleKey;
  return metaTitle ? t(metaTitle) : t('nav.dashboard');
});

const pageSubtitle = computed(() => t(pageSubtitles[route.name] || 'shell.overviewSubtitle'));

const showPageHead = computed(() => !route.meta?.chatLayout && route.name !== 'task-detail');

const hideBottomNav = computed(() => Boolean(route.meta?.hideBottomNav));

const profileName = computed(() => profile.value?.displayName || t('shell.personalAccount'));

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

onMounted(() => {
  if (!session.authenticated) {
    return;
  }
  portalApi.currentPrincipal()
    .then((body) => {
      profile.value = body;
    })
    .catch(() => {
      profile.value = null;
    });
});
</script>

<template>
  <div class="em-app">
    <SkipToContent />

    <aside class="em-sidebar" aria-label="Primary">
      <div class="em-sidebar__brand md-brand">
        <BrandLockup>
          <p class="md-brand__subtitle">{{ t('nav.groupWorkspace') }}</p>
        </BrandLockup>
      </div>

      <div class="fn-workspace">
        <span class="fn-avatar" aria-hidden="true">{{ initials }}</span>
        <div>
          <strong>{{ profileName }}</strong>
          <small>{{ profile?.email || t('shell.personalAccount') }}</small>
        </div>
      </div>

      <nav class="fn-nav">
        <template v-for="group in visibleNavGroups" :key="group.labelKey">
          <p class="fn-nav-group">{{ t(group.labelKey) }}</p>
          <ul class="em-sidebar__list">
            <li v-for="item in group.items" :key="item.name">
              <RouterLink
                :to="{ name: item.name }"
                class="em-sidebar__link"
                :class="{ active: isNavActive(item.name) }"
              >
                <StrokeIcon :name="item.icon" />
                {{ t(item.labelKey) }}
              </RouterLink>
            </li>
          </ul>
        </template>
      </nav>

      <button type="button" class="md-btn md-btn-text em-sidebar__signout" @click="signOut">
        <StrokeIcon name="logout" />
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
          <StrokeIcon name="menu" />
        </button>
        <div class="fn-crumb">
          <span>{{ t('shell.portal') }}</span>
          <span aria-hidden="true">/</span>
          <strong>{{ pageTitle }}</strong>
        </div>
      </header>

      <main
        id="main-content"
        class="em-content"
        :class="{ 'em-content--no-nav': hideBottomNav, 'em-content--chat': route.meta?.chatLayout }"
        tabindex="-1"
      >
        <header v-if="showPageHead" class="fn-page-head">
          <div>
            <p class="fn-eyebrow">{{ t('shell.eyebrow') }}</p>
            <h1>{{ pageTitle }}</h1>
            <p class="fn-sub">{{ pageSubtitle }}</p>
          </div>
          <RouterLink v-if="route.name === 'dashboard'" class="md-btn md-btn-filled" :to="{ name: 'tasks' }">
            <StrokeIcon name="plus" />
            {{ t('dashboard.createTask') }}
          </RouterLink>
        </header>
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
          <StrokeIcon :name="item.icon" />
          <span>{{ t(item.labelKey) }}</span>
        </RouterLink>
      </nav>
    </div>

    <nav class="em-drawer" :class="{ 'em-drawer--open': drawerOpen }" aria-label="Menu">
      <div class="em-drawer__backdrop" @click="closeDrawer" />
      <aside class="em-drawer__panel">
        <div class="em-drawer__header">
          <div class="md-brand">
            <BrandLockup>
              <p class="md-brand__subtitle">{{ t('nav.groupWorkspace') }}</p>
            </BrandLockup>
          </div>
          <button type="button" class="em-icon-btn" aria-label="Close menu" @click="closeDrawer">
            <StrokeIcon name="close" />
          </button>
        </div>
        <div class="fn-workspace">
          <span class="fn-avatar" aria-hidden="true">{{ initials }}</span>
          <div>
            <strong>{{ profileName }}</strong>
            <small>{{ profile?.email || t('shell.personalAccount') }}</small>
          </div>
        </div>
        <template v-for="group in visibleNavGroups" :key="`drawer-${group.labelKey}`">
          <p class="fn-nav-group">{{ t(group.labelKey) }}</p>
          <ul class="em-drawer__list">
            <li v-for="item in group.items" :key="item.name">
              <RouterLink :to="{ name: item.name }" class="em-drawer__link" @click="onNavigate">
                <StrokeIcon :name="item.icon" />
                {{ t(item.labelKey) }}
              </RouterLink>
            </li>
          </ul>
        </template>
        <button type="button" class="md-btn md-btn-text em-drawer__signout" @click="signOut">
          <StrokeIcon name="logout" />
          {{ t('auth.signOut') }}
        </button>
      </aside>
    </nav>
  </div>
</template>
