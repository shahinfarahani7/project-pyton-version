<script setup>
import { computed } from 'vue';
import { RouterLink, RouterView } from 'vue-router';

import markUrl from '../assets/brand/fibonai-mark.png';
import { useSession } from '../auth/session';

const NAV = [
  { to: '/', label: 'Overview', group: 'Network', permission: 'operations.read' },
  { to: '/tasks', label: 'Task monitor', group: 'Network', permission: 'operations.read' },
  { to: '/workers', label: 'Workers', group: 'Network', permission: 'operations.read' },
  { to: '/models', label: 'Models', group: 'Network', permission: 'operations.read' },
  { to: '/fraud', label: 'Fraud cases', group: 'Review', permission: 'operations.read' },
  { to: '/disputes', label: 'Disputes', group: 'Review', permission: 'operations.read' },
  { to: '/reconciliation', label: 'Reconciliation', group: 'Review', permission: 'operations.read' },
  { to: '/incidents', label: 'Incidents', group: 'Review', permission: 'operations.read' },
  { to: '/approvals', label: 'Approvals', group: 'Governance', permission: 'operations.approve' },
  { to: '/emergency', label: 'Emergency access', group: 'Governance', permission: 'operations.break_glass' },
];

const session = useSession();

const visibleNav = computed(() => NAV.filter((item) => session.hasPermission(item.permission)));

const visibleGroups = computed(() => {
  const groups = [];
  for (const item of visibleNav.value) {
    const current = groups[groups.length - 1];
    if (!current || current.label !== item.group) {
      groups.push({ label: item.group, items: [item] });
    } else {
      current.items.push(item);
    }
  }
  return groups;
});
</script>

<template>
  <RouterView v-if="!session.authenticated" />
  <template v-else>
    <a class="skip-link" href="#main-content">Skip to main content</a>
    <header class="topbar">
      <strong class="brand-lockup"><img :src="markUrl" alt="" />FibonAI Operations</strong>
      <span class="badge">{{ session.mfaVerified ? 'MFA verified' : 'MFA required' }}</span>
      <button type="button" @click="session.logout()">Sign out</button>
    </header>
    <div class="layout">
      <nav aria-label="Operations">
        <template v-for="group in visibleGroups" :key="group.label">
          <p class="nav-group">{{ group.label }}</p>
          <ul>
            <li v-for="item in group.items" :key="item.to">
              <RouterLink :to="item.to" exact-active-class="active">{{ item.label }}</RouterLink>
            </li>
          </ul>
        </template>
      </nav>
      <main id="main-content" tabindex="-1">
        <RouterView />
      </main>
    </div>
  </template>
</template>
