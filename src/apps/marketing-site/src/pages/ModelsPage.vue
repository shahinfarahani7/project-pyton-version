<script setup>
import SectionHeading from '../components/SectionHeading.vue';
import { modelCategories } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Models & task types</p>
        <h1 class="page-hero__title">Signed models for every workload in the catalog</h1>
        <p class="page-hero__lead">
          EdgeMint ships curated on-device models for document, vision, language, and moderation tasks. Each model is
          hash-verified and signed before workers execute assignments.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container">
        <SectionHeading
          eyebrow="Catalog"
          title="60+ task types across four domains"
          subtitle="Browse by category. Production deployments can pin model versions and verification tiers per workspace policy."
        />
        <div class="card-grid card-grid--2">
          <article v-for="group in modelCategories" :key="group.title" class="use-case-card">
            <h3>{{ group.title }}</h3>
            <p class="use-case-card__meta">{{ group.count }} task types · {{ group.input }}</p>
            <ul>
              <li v-for="item in group.samples" :key="item">{{ item }}</li>
            </ul>
          </article>
        </div>
      </div>
    </section>

    <section class="section section--alt">
      <div class="container container--narrow prose">
        <h2>Verification tiers</h2>
        <p>
          Every task type supports a verification ladder — from standard single-worker inference through multi-worker
          consensus and optional human review. Higher tiers add latency and cost but reduce false-positive risk for
          regulated workflows.
        </p>
        <ul class="check-list">
          <li><strong>Standard</strong> — single signed model execution on an opted-in worker.</li>
          <li><strong>Consensus</strong> — independent workers must agree before a result is accepted.</li>
          <li><strong>Human review</strong> — escalated cases routed to a review queue with audit metadata.</li>
        </ul>
      </div>
    </section>
  </div>
</template>
