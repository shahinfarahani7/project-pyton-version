<script setup>
import { computed } from 'vue';
import { RouterLink, useRoute } from 'vue-router';

import { legalLinks } from '../content/site.js';

const route = useRoute();

const active = computed(() => {
  const slug = String(route.params.slug ?? 'privacy');
  return legalLinks.find((item) => item.slug === slug) ?? legalLinks[0];
});

const bodies = {
  privacy:
    'EdgeMint processes customer task payloads, billing records, and audit events according to workspace data region policies. Worker devices receive only the minimum input required for assigned tasks; customer identity is not disclosed to workers. Temporary worker payloads are deleted within fifteen minutes unless a longer retention window is contractually required.',
  terms:
    'Use of EdgeMint services is subject to acceptable use policies, published pricing, and workspace-scoped access controls. Customers are responsible for lawful processing of data submitted to the platform. Service levels, support tiers, and liability caps are defined in enterprise agreements.',
  workers:
    'Worker participation is optional and controlled by an explicit availability toggle. Rewards are variable, denominated in EUR, and not guaranteed. EdgeMint does not offer investment products, cryptocurrency mining, or passive income programs through the worker app.',
  dpa:
    'Enterprise customers may execute EdgeMint’s Data Processing Addendum covering sub-processors, cross-border transfers, breach notification, and deletion obligations. Contact security@edgemint.io for the current DPA template and subprocessor registry.',
};
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Legal</p>
        <h1 class="page-hero__title">{{ active.label }}</h1>
        <p class="page-hero__lead">Preview legal summary — formal counsel-approved documents available on request.</p>
      </div>
    </section>

    <section class="section">
      <div class="container container--narrow">
        <nav class="legal-nav" aria-label="Legal documents">
          <RouterLink
            v-for="item in legalLinks"
            :key="item.slug"
            class="legal-nav__link"
            :class="{ 'legal-nav__link--active': item.slug === active.slug }"
            :to="{ name: 'legal', params: { slug: item.slug } }"
          >
            {{ item.label }}
          </RouterLink>
        </nav>
        <article class="prose legal-body">
          <p>{{ bodies[active.slug] ?? bodies.privacy }}</p>
          <p>
            For signed PDFs, jurisdiction-specific terms, or store-review evidence packs, contact
            <a href="mailto:legal@edgemint.io">legal@edgemint.io</a>.
          </p>
        </article>
      </div>
    </section>
  </div>
</template>
