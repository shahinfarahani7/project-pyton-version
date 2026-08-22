import { createRouter, createWebHistory } from 'vue-router';

import { session } from '../auth/session';
import AppShell from '../components/AppShell.vue';
import ApiKeysPage from '../pages/ApiKeysPage.vue';
import BillingPage from '../pages/BillingPage.vue';
import DashboardPage from '../pages/DashboardPage.vue';
import DisputesPage from '../pages/DisputesPage.vue';
import FilesPage from '../pages/FilesPage.vue';
import LoginPage from '../pages/LoginPage.vue';
import MorePage from '../pages/MorePage.vue';
import SettingsPage from '../pages/SettingsPage.vue';
import TaskDetailPage from '../pages/TaskDetailPage.vue';
import TasksPage from '../pages/TasksPage.vue';
import TeamPage from '../pages/TeamPage.vue';
import UsagePage from '../pages/UsagePage.vue';
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
        { path: '', name: 'dashboard', component: DashboardPage, meta: { titleKey: 'nav.dashboard' } },
        { path: 'tasks', name: 'tasks', component: TasksPage, meta: { titleKey: 'nav.tasks' } },
        { path: 'tasks/new', redirect: { name: 'tasks' } },
        {
          path: 'tasks/:id',
          name: 'task-detail',
          component: TaskDetailPage,
          meta: { titleKey: 'tasks.detailTitle', hideBottomNav: true, hideShellHeader: true },
        },
        { path: 'usage', name: 'usage', component: UsagePage, meta: { titleKey: 'nav.usage' } },
        { path: 'billing', name: 'billing', component: BillingPage, meta: { titleKey: 'nav.billing' } },
        { path: 'more', name: 'more', component: MorePage, meta: { titleKey: 'nav.more' } },
        { path: 'files', name: 'files', component: FilesPage, meta: { titleKey: 'nav.files', hideBottomNav: true } },
        { path: 'webhooks', name: 'webhooks', component: WebhooksPage, meta: { titleKey: 'nav.webhooks', hideBottomNav: true } },
        { path: 'api-keys', name: 'api-keys', component: ApiKeysPage, meta: { titleKey: 'nav.apiKeys', hideBottomNav: true } },
        { path: 'disputes', name: 'disputes', component: DisputesPage, meta: { titleKey: 'nav.disputes', hideBottomNav: true } },
        { path: 'team', name: 'team', component: TeamPage, meta: { titleKey: 'nav.team', hideBottomNav: true } },
        { path: 'settings', name: 'settings', component: SettingsPage, meta: { titleKey: 'nav.settings', hideBottomNav: true } },
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
