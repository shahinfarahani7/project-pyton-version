<script setup>
import { RouterLink } from 'vue-router';

defineProps({
  title: { type: String, required: true },
  body: { type: String, required: true },
  ctaLabel: { type: String, default: 'Get in touch' },
  ctaTo: { type: String, default: 'contact' },
});
</script>

<template>
  <section class="cta-band">
    <div class="cta-band__inner">
      <div class="cta-band__decor" aria-hidden="true">
        <span class="cta-band__orb cta-band__orb--1" />
        <span class="cta-band__orb cta-band__orb--2" />
        <span class="cta-band__spark cta-band__spark--1" />
        <span class="cta-band__spark cta-band__spark--2" />
        <span class="cta-band__spark cta-band__spark--3" />
      </div>
      <div class="cta-band__content">
        <h2 class="cta-band__title">{{ title }}</h2>
        <p class="cta-band__body">{{ body }}</p>
      </div>
      <RouterLink class="btn btn--primary btn--lg cta-band__btn" :to="{ name: ctaTo }">{{ ctaLabel }}</RouterLink>
    </div>
  </section>
</template>
