<script setup>
import { trustBadges } from '../content/site.js';

const items = [...trustBadges, ...trustBadges];
</script>

<template>
  <section class="trust-marquee" aria-label="Platform highlights">
    <div class="trust-marquee__fade trust-marquee__fade--left" aria-hidden="true" />
    <div class="trust-marquee__fade trust-marquee__fade--right" aria-hidden="true" />
    <div class="trust-marquee__track">
      <span v-for="(item, index) in items" :key="`${item.label}-${index}`" class="trust-marquee__item">
        <span class="trust-marquee__icon" aria-hidden="true">{{ item.icon }}</span>
        {{ item.label }}
      </span>
    </div>
  </section>
</template>
