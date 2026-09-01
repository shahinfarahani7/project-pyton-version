<script setup>
import CtaBand from '../components/CtaBand.vue';
import SectionHeading from '../components/SectionHeading.vue';
import { securityFeatures } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Security</p>
        <h1 class="page-hero__title">Production security by default</h1>
        <p class="page-hero__lead">
          EdgeMint is designed for regulated workloads: tenant isolation, signed artifacts, durable audit logs, and
          explicit — never silent — routing decisions.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container">
        <div class="card-grid card-grid--2">
          <article v-for="item in securityFeatures" :key="item.title" class="feature-card feature-card--tall">
            <h2>{{ item.title }}</h2>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </div>
    </section>

    <section class="section section--alt">
      <div class="container container--narrow prose">
        <SectionHeading title="Architecture highlights" align="left" />
        <ul class="check-list">
          <li>PostgreSQL 18 as the single system of record — transactional outbox/inbox for events</li>
          <li>Secure WebSocket relay with acknowledgement, replay, and dead-letter queues</li>
          <li>OIDC/PKCE for customer and operations portals</li>
          <li>Device-bound keys and platform attestation for worker enrollment</li>
          <li>Progressive canary releases with automatic rollback on SLO breach</li>
          <li>Fraud, reconciliation, and emergency controls in the operations console</li>
        </ul>
      </div>
    </section>

    <CtaBand
      title="Security questionnaire?"
      body="Contact our team for architecture diagrams, DPA materials, and penetration test summaries under NDA."
      cta-label="Contact security"
    />
  </div>
</template>
