<script setup>
import { RouterLink } from 'vue-router';

import { portalLoginUrl } from '../config/env.js';
import { legalLinks, navLinks } from '../content/site.js';
</script>

<template>
  <footer class="site-footer">
    <div class="site-footer__grid">
      <div class="site-footer__brand">
        <RouterLink class="site-brand site-brand--footer" to="/">
          <span class="site-brand__mark" aria-hidden="true">EM</span>
          <span class="site-brand__text">EdgeMint</span>
        </RouterLink>
        <p class="site-footer__tagline">
          Edge-first AI inference with quote-before-run pricing and auditable execution for regulated teams.
        </p>
      </div>

      <div>
        <h2 class="site-footer__heading">Product</h2>
        <ul class="site-footer__list">
          <li v-for="link in navLinks" :key="link.name">
            <RouterLink :to="{ name: link.name }">{{ link.label }}</RouterLink>
          </li>
        </ul>
      </div>

      <div>
        <h2 class="site-footer__heading">Legal</h2>
        <ul class="site-footer__list">
          <li v-for="item in legalLinks" :key="item.slug">
            <RouterLink :to="{ name: 'legal', params: { slug: item.slug } }">{{ item.label }}</RouterLink>
          </li>
        </ul>
      </div>

      <div>
        <h2 class="site-footer__heading">Get started</h2>
        <ul class="site-footer__list">
          <li><RouterLink :to="{ name: 'contact' }">Request a demo</RouterLink></li>
          <li><RouterLink :to="{ name: 'docs' }">Documentation</RouterLink></li>
          <li><RouterLink :to="{ name: 'status' }">System status</RouterLink></li>
          <li><a :href="portalLoginUrl">Customer portal</a></li>
        </ul>
      </div>
    </div>

    <div class="site-footer__bottom">
      <p>© {{ new Date().getFullYear() }} EdgeMint. All rights reserved.</p>
      <p class="site-footer__disclaimer">
        Worker rewards are variable and not guaranteed. EdgeMint is not cryptocurrency mining.
      </p>
    </div>
  </footer>
</template>
