<script setup>
import { RouterView } from 'vue-router';

import MotionBackground from './components/MotionBackground.vue';
import SiteFooter from './components/SiteFooter.vue';
import SiteHeader from './components/SiteHeader.vue';
</script>

<template>
  <div class="site">
    <MotionBackground />
    <a class="skip-link" href="#main">Skip to content</a>
    <SiteHeader />
    <main id="main">
      <RouterView />
    </main>
    <SiteFooter />
  </div>
</template>
