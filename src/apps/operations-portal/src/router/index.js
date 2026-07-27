import { createRouter, createWebHistory } from 'vue-router';

import { session } from '../auth/session';
import AppShell from '../components/AppShell.vue';
import ApprovalsPage from '../pages/ApprovalsPage.vue';
import DashboardPage from '../pages/DashboardPage.vue';
import DisputesPage from '../pages/DisputesPage.vue';
import EmergencyPage from '../pages/EmergencyPage.vue';
import FraudPage from '../pages/FraudPage.vue';
import IncidentsPage from '../pages/IncidentsPage.vue';
import LoginPage from '../pages/LoginPage.vue';
import ModelsPage from '../pages/ModelsPage.vue';
import ReconciliationPage from '../pages/ReconciliationPage.vue';
import TasksPage from '../pages/TasksPage.vue';
import WorkersPage from '../pages/WorkersPage.vue';

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
        { path: 'workers', name: 'workers', component: WorkersPage, meta: { requiresAuth: true } },
        { path: 'models', name: 'models', component: ModelsPage, meta: { requiresAuth: true } },
        { path: 'fraud', name: 'fraud', component: FraudPage, meta: { requiresAuth: true } },
        { path: 'disputes', name: 'disputes', component: DisputesPage, meta: { requiresAuth: true } },
        { path: 'reconciliation', name: 'reconciliation', component: ReconciliationPage, meta: { requiresAuth: true } },
        { path: 'incidents', name: 'incidents', component: IncidentsPage, meta: { requiresAuth: true } },
        { path: 'approvals', name: 'approvals', component: ApprovalsPage, meta: { requiresAuth: true } },
        { path: 'emergency', name: 'emergency', component: EmergencyPage, meta: { requiresAuth: true } },
        { path: ':pathMatch(.*)*', redirect: '/' },
      ],
    },
  ],
});

router.beforeEach((to) => {
  const requiresAuth = to.matched.some((record) => record.meta.requiresAuth);
  if (requiresAuth && (!session.authenticated || !session.mfaVerified)) {
    return { path: '/login' };
  }
  if (to.path === '/login' && session.authenticated && session.mfaVerified) {
    return { path: '/' };
  }
  return true;
});

export default router;
