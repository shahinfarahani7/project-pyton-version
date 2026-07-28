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
      path: '/login',
      name: 'login',
      component: LoginPage,
      meta: { guest: true },
    },
    {
      path: '/',
      component: AppShell,
      meta: { requiresAuth: true },
      children: [
        { path: '', name: 'dashboard', component: DashboardPage },
        { path: 'tasks', name: 'tasks', component: TasksPage },
        { path: 'files', name: 'files', component: FilesPage },
        { path: 'webhooks', name: 'webhooks', component: WebhooksPage },
        { path: 'api-keys', name: 'api-keys', component: ApiKeysPage },
        { path: 'billing', name: 'billing', component: BillingPage },
        { path: 'disputes', name: 'disputes', component: DisputesPage },
        { path: 'team', name: 'team', component: TeamPage },
        { path: 'settings', name: 'settings', component: SettingsPage },
      ],
    },
    {
      path: '/:pathMatch(.*)*',
      redirect: () => (session.authenticated ? { name: 'dashboard' } : { name: 'login' }),
    },
  ],
});

router.beforeEach((to) => {
  const requiresAuth = to.matched.some((record) => record.meta.requiresAuth);
  if (requiresAuth && !session.authenticated) {
    return { name: 'login', query: { redirect: to.fullPath } };
  }
  if (to.meta.guest && session.authenticated) {
    return { name: 'dashboard' };
  }
  return true;
});

export default router;
