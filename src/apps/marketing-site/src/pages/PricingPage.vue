<script setup>
import CtaBand from '../components/CtaBand.vue';
import PageHero from '../components/PageHero.vue';
import SectionHeading from '../components/SectionHeading.vue';
import { pricingNotes, pricingRows } from '../content/site.js';

const planCards = [
  { icon: '⬡', title: 'Workspace plans', body: 'Developer, startup, growth, business, and enterprise tiers adjust base multipliers from 70% to 115%.' },
  { icon: '⟡', title: 'Priority & SLA', body: 'Batch, standard, priority, and realtime lanes change throughput expectations and quote multipliers.' },
  { icon: '⛨', title: 'Verification', body: 'Standard through human review — buy the quality level your compliance team requires.' },
];
</script>

<template>
  <div class="page">
    <PageHero
      eyebrow="Pricing"
      title="Transparent EUR unit rates"
      lead="Base prices from the published PriceBook. Every task receives a quote before execution — including plan, priority, verification, and routing modifiers."
      :badges="['EUR', 'Immutable quotes', 'No surprises']"
    />

    <section v-reveal class="section">
      <div class="container container--narrow">
        <div class="pricing-preview pricing-preview--glow" v-reveal="80">
          <table class="pricing-table pricing-table--full">
            <thead>
              <tr>
                <th scope="col">Task type</th>
                <th scope="col">Billing measure</th>
                <th scope="col">Unit price (from)</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in pricingRows" :key="row.task">
                <td>{{ row.task }}</td>
                <td>{{ row.measure }}</td>
                <td><strong>{{ row.price }}</strong></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul class="note-list">
          <li v-for="note in pricingNotes" :key="note">{{ note }}</li>
        </ul>
      </div>
    </section>

    <section v-reveal class="section section--alt">
      <div class="container">
        <SectionHeading
          title="Plans &amp; modifiers"
          subtitle="Final quotes combine base rates with the options below."
        />
        <div class="card-grid card-grid--3">
          <article v-for="(item, index) in planCards" :key="item.title" class="feature-card feature-card--glow" v-reveal="index * 90">
            <span class="feature-card__icon" aria-hidden="true">{{ item.icon }}</span>
            <h3>{{ item.title }}</h3>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </div>
    </section>

    <div v-reveal>
      <CtaBand
        title="Need committed capacity?"
        body="Talk to us about dedicated worker pools, enterprise verification, and custom region policies."
      />
    </div>
  </div>
</template>
