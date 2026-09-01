<script setup>
import { onMounted, onUnmounted, ref } from 'vue';
import { RouterLink } from 'vue-router';

import { portalLoginUrl } from '../config/env.js';
import { navLinks } from '../content/site.js';

const menuOpen = ref(false);
const scrolled = ref(false);
let raf = 0;

function closeMenu() {
  menuOpen.value = false;
}

function updateScroll() {
  scrolled.value = window.scrollY > 24;
}

function onScroll() {
  cancelAnimationFrame(raf);
  raf = requestAnimationFrame(updateScroll);
}

onMounted(() => {
  updateScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
});

onUnmounted(() => {
  window.removeEventListener('scroll', onScroll);
  cancelAnimationFrame(raf);
});
</script>

<template>
  <header class="site-header" :class="{ 'site-header--scrolled': scrolled }">
    <div class="site-header__inner">
      <RouterLink class="site-brand" to="/" @click="closeMenu">
        <span class="site-brand__mark" aria-hidden="true">EM</span>
        <span class="site-brand__text">EdgeMint</span>
      </RouterLink>

      <button
        type="button"
        class="site-header__menu-btn"
        :aria-expanded="menuOpen"
        aria-controls="site-nav"
        aria-label="Toggle navigation"
        @click="menuOpen = !menuOpen"
      >
        <span aria-hidden="true">{{ menuOpen ? '✕' : '☰' }}</span>
      </button>

      <nav id="site-nav" class="site-nav" :class="{ 'site-nav--open': menuOpen }" aria-label="Primary">
        <RouterLink
          v-for="link in navLinks"
          :key="link.name"
          class="site-nav__link"
          :to="{ name: link.name }"
          @click="closeMenu"
        >
          {{ link.label }}
        </RouterLink>
      </nav>

      <div class="site-header__actions">
        <RouterLink class="btn btn--ghost" :to="{ name: 'contact' }">Contact</RouterLink>
        <a class="btn btn--primary" :href="portalLoginUrl">Customer login</a>
      </div>
    </div>
  </header>
</template>
