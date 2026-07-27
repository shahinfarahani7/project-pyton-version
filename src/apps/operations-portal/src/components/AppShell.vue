<script setup>
import { computed } from 'vue';
import { RouterLink, RouterView } from 'vue-router';

import { useSession } from '../auth/session';

const NAV = [
  { to: '/', label: 'Overview', permission: 'operations.read' },
  { to: '/tasks', label: 'Tasks', permission: 'operations.read' },
  { to: '/workers', label: 'Workers', permission: 'operations.read' },
  { to: '/models', label: 'Models', permission: 'operations.read' },
  { to: '/fraud', label: 'Fraud', permission: 'operations.read' },
  { to: '/disputes', label: 'Disputes', permission: 'operations.read' },
  { to: '/reconciliation', label: 'Reconciliation', permission: 'operations.read' },
  { to: '/incidents', label: 'Incidents', permission: 'operations.read' },
  { to: '/approvals', label: 'Approvals', permission: 'operations.approve' },
  { to: '/emergency', label: 'Emergency', permission: 'operations.break_glass' },
];

const session = useSession();

const visibleNav = computed(() => NAV.filter((item) => session.hasPermission(item.permission)));
</script>

<template>
  <RouterView v-if="!session.authenticated" />
  <template v-else>
    <a class="skip-link" href="#main-content">Skip to main content</a>
    <header class="topbar">
      <strong>EdgeMint Operations</strong>
      <span class="badge">{{ session.mfaVerified ? 'MFA verified' : 'MFA required' }}</span>
      <button type="button" @click="session.logout()">Sign out</button>
    </header>
    <div class="layout">
      <nav aria-label="Operations">
        <ul>
          <li v-for="item in visibleNav" :key="item.to">
            <RouterLink :to="item.to" exact-active-class="active">{{ item.label }}</RouterLink>
          </li>
        </ul>
      </nav>
      <main id="main-content" tabindex="-1">
        <RouterView />
      </main>
    </div>
  </template>
</template>
