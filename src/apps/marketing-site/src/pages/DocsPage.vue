<script setup>
import { RouterLink } from 'vue-router';

import CtaBand from '../components/CtaBand.vue';
import { docsSections } from '../content/site.js';
import { portalUrl } from '../config/env.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Documentation</p>
        <h1 class="page-hero__title">Build on the EdgeMint task API</h1>
        <p class="page-hero__lead">
          OpenAPI-first contracts, async lifecycle events, and portal-based local development — everything you need to
          integrate document, vision, and language workloads.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container">
        <div class="card-grid card-grid--2">
          <article v-for="section in docsSections" :key="section.title" class="feature-card">
            <h3>{{ section.title }}</h3>
            <p>{{ section.body }}</p>
            <ul v-if="section.links?.length" class="docs-links">
              <li v-for="link in section.links" :key="link.label">
                <RouterLink v-if="link.to" :to="{ name: link.to }">{{ link.label }}</RouterLink>
                <a v-else-if="link.href" :href="link.href" target="_blank" rel="noopener noreferrer">{{ link.label }}</a>
                <span v-else>{{ link.label }}</span>
              </li>
            </ul>
          </article>
        </div>
      </div>
    </section>

    <section class="section section--alt">
      <div class="container container--narrow prose">
        <h2>Quick start (local)</h2>
        <ol>
          <li>Start the Docker backend and customer portal on your machine.</li>
          <li>Use <strong>Dev sign-in</strong> in the portal to create a workspace session.</li>
          <li>Submit a task from the catalog and watch live SSE lifecycle events.</li>
        </ol>
        <p>
          Portal URL for local development:
          <a :href="portalUrl" target="_blank" rel="noopener noreferrer">{{ portalUrl }}</a>
        </p>
      </div>
    </section>

    <CtaBand
      title="Need production API credentials?"
      body="We provision workspace keys, webhook endpoints, and integration review for your environment."
      cta-label="Request access"
    />
  </div>
</template>
