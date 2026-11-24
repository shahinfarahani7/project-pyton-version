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
      title="Assess, dispatch, agree, deliver"
      lead="FibonAI is an async task platform. Customers submit workloads — the first month is free — each task is assessed for difficulty and sent to at least three edge workers, and only the agreed answer comes back — with every decision recorded."
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
          Choose how aggressively FibonAI uses edge workers versus cloud capacity:
          <strong>edge-only</strong>, <strong>edge-preferred</strong> (default), or
          <strong>fastest available</strong>. Private pools are available for enterprise workspaces.
        </p>
        <h2>Consensus verification</h2>
        <p>
          Every task goes to at least three independent workers. A result is accepted when at least two agree; if
          none do, two new workers are added each round, up to ten rounds. Enterprise review and human-in-the-loop
          are available for higher-risk work.
        </p>
        <h2>Credits, not prices</h2>
        <p>
          New accounts get their first month free. The quick assessment places each task in a difficulty class, and a
          harder task uses more credits. You always see the credits before you confirm. After the first month, add
          monthly credit.
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
