import { createRouter, createWebHistory } from 'vue-router';

import ContactPage from '../pages/ContactPage.vue';
import DevelopersPage from '../pages/DevelopersPage.vue';
import DocsPage from '../pages/DocsPage.vue';
import HomePage from '../pages/HomePage.vue';
import HowItWorksPage from '../pages/HowItWorksPage.vue';
import LegalPage from '../pages/LegalPage.vue';
import ModelsPage from '../pages/ModelsPage.vue';
import PricingPage from '../pages/PricingPage.vue';
import SecurityPage from '../pages/SecurityPage.vue';
import StatusPage from '../pages/StatusPage.vue';
import UseCasesPage from '../pages/UseCasesPage.vue';
import WorkersPage from '../pages/WorkersPage.vue';
import { portalLoginUrl, portalRegisterUrl } from '../config/env.js';

const router = createRouter({
  history: createWebHistory(),
  scrollBehavior() {
    return { top: 0 };
  },
  routes: [
    { path: '/', name: 'home', component: HomePage, meta: { title: 'Edge-first AI inference platform' } },
    { path: '/how-it-works', name: 'how-it-works', component: HowItWorksPage, meta: { title: 'How it works' } },
    { path: '/use-cases', name: 'use-cases', component: UseCasesPage, meta: { title: 'Use cases' } },
    { path: '/pricing', name: 'pricing', component: PricingPage, meta: { title: 'Pricing' } },
    { path: '/models', name: 'models', component: ModelsPage, meta: { title: 'Models & task types' } },
    { path: '/security', name: 'security', component: SecurityPage, meta: { title: 'Security' } },
    { path: '/workers', name: 'workers', component: WorkersPage, meta: { title: 'Worker participation' } },
    { path: '/developers', name: 'developers', component: DevelopersPage, meta: { title: 'Developers' } },
    { path: '/docs', name: 'docs', component: DocsPage, meta: { title: 'Documentation' } },
    { path: '/status', name: 'status', component: StatusPage, meta: { title: 'System status' } },
    { path: '/contact', name: 'contact', component: ContactPage, meta: { title: 'Contact' } },
    { path: '/legal/:slug?', name: 'legal', component: LegalPage, meta: { title: 'Legal' } },
    { path: '/login', redirect: () => portalLoginUrl },
    { path: '/register', redirect: () => portalRegisterUrl },
    { path: '/:pathMatch(.*)*', redirect: { name: 'home' } },
  ],
});

router.afterEach((to) => {
  const pageTitle = to.meta?.title;
  document.title = pageTitle ? `${pageTitle} · EdgeMint` : 'EdgeMint — Edge-first AI inference platform';

  const description = to.meta?.description;
  if (description) {
    let tag = document.querySelector('meta[name="description"]');
    if (!tag) {
      tag = document.createElement('meta');
      tag.setAttribute('name', 'description');
      document.head.appendChild(tag);
    }
    tag.setAttribute('content', description);
  }
});

export default router;
