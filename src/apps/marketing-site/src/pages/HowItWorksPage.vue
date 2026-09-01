<script setup>
import CtaBand from '../components/CtaBand.vue';
import PageHero from '../components/PageHero.vue';
import SectionHeading from '../components/SectionHeading.vue';
import { flowSteps, pillars } from '../content/site.js';
</script>

<template>
  <div class="page">
    <PageHero
      eyebrow="How it works"
      title="Quote, route, execute, audit"
      lead="EdgeMint is an async task platform. Customers submit workloads, receive deterministic quotes, and track execution across edge workers and optional cloud fallback — with every decision recorded."
      :badges="['Async', 'Edge-first', 'Auditable']"
    />

    <section v-reveal class="section">
      <div class="container">
        <ol class="flow-list flow-list--large">
          <li v-for="(step, index) in flowSteps" :key="step.step" class="flow-list__item" v-reveal="index * 100">
            <span class="flow-list__step">{{ step.step }}</span>
            <div>
              <h2>{{ step.title }}</h2>
              <p>{{ step.body }}</p>
            </div>
          </li>
        </ol>
      </div>
    </section>

    <section v-reveal class="section section--alt">
      <div class="container">
        <SectionHeading title="What makes the workflow different" align="left" />
        <div class="card-grid card-grid--3">
          <article v-for="(item, index) in pillars" :key="item.title" class="feature-card feature-card--glow" v-reveal="index * 90">
            <span class="feature-card__icon" aria-hidden="true">{{ item.icon }}</span>
            <h3>{{ item.title }}</h3>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </div>
    </section>

    <section v-reveal class="section">
      <div class="container container--narrow prose">
        <h2>Execution policies</h2>
        <p>
          Choose how aggressively EdgeMint uses edge workers versus cloud capacity:
          <strong>edge-only</strong>, <strong>edge-preferred</strong> (default), or
          <strong>fastest available</strong>. Private pools are available for enterprise workspaces.
        </p>
        <h2>Verification tiers</h2>
        <p>
          Match quality to risk: standard inference, verified output, multi-worker consensus, enterprise review, or
          human-in-the-loop. Each tier adjusts the quote multiplier and SLA expectations transparently.
        </p>
      </div>
    </section>

    <div v-reveal>
      <CtaBand
        title="See it in the portal"
        body="Use development sign-in to create tasks, watch live status updates, and inspect request and result payloads."
        cta-label="Contact us for access"
      />
    </div>
  </div>
</template>
