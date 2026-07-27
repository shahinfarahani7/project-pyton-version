import { createRouter, createWebHistory } from 'vue-router';

import { session } from '../auth/session';
import AppShell from '../components/AppShell.vue';
import ApiKeysPage from '../pages/ApiKeysPage.vue';
import BillingPage from '../pages/BillingPage.vue';
import DashboardPage from '../pages/DashboardPage.vue';
import DisputesPage from '../pages/DisputesPage.vue';
import FilesPage from '../pages/FilesPage.vue';
import LoginPage from '../pages/LoginPage.vue';
import SettingsPage from '../pages/SettingsPage.vue';
import TasksPage from '../pages/TasksPage.vue';
import TeamPage from '../pages/TeamPage.vue';
import WebhooksPage from '../pages/WebhooksPage.vue';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      component: AppShell,
      children: [
        { path: 'login', name: 'login', component: LoginPage },
        { path: '', name: 'dashboard', component: DashboardPage, meta: { requiresAuth: true } },
        { path: 'tasks', name: 'tasks', component: TasksPage, meta: { requiresAuth: true } },
        { path: 'files', name: 'files', component: FilesPage, meta: { requiresAuth: true } },
        { path: 'webhooks', name: 'webhooks', component: WebhooksPage, meta: { requiresAuth: true } },
        { path: 'api-keys', name: 'api-keys', component: ApiKeysPage, meta: { requiresAuth: true } },
        { path: 'billing', name: 'billing', component: BillingPage, meta: { requiresAuth: true } },
        { path: 'disputes', name: 'disputes', component: DisputesPage, meta: { requiresAuth: true } },
        { path: 'team', name: 'team', component: TeamPage, meta: { requiresAuth: true } },
        { path: 'settings', name: 'settings', component: SettingsPage, meta: { requiresAuth: true } },
        { path: ':pathMatch(.*)*', redirect: '/' },
      ],
    },
  ],
});

router.beforeEach((to) => {
  const requiresAuth = to.matched.some((record) => record.meta.requiresAuth);
  if (requiresAuth && !session.authenticated) {
    return { path: '/login' };
  }
  if (to.path === '/login' && session.authenticated) {
    return { path: '/' };
  }
  return true;
});

export default router;
