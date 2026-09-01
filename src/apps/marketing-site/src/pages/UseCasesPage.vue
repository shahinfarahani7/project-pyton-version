<script setup>
import CtaBand from '../components/CtaBand.vue';
import SectionHeading from '../components/SectionHeading.vue';
import { useCaseGroups } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Use cases</p>
        <h1 class="page-hero__title">Production workloads across your document and AI stack</h1>
        <p class="page-hero__lead">
          EdgeMint ships with a broad task catalog — from receipt OCR and invoice extraction to content moderation,
          catalog enrichment, and ML validation pipelines.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container">
        <div class="card-grid card-grid--2">
          <article v-for="group in useCaseGroups" :key="group.title" class="use-case-card use-case-card--large">
            <h2>{{ group.title }}</h2>
            <ul>
              <li v-for="item in group.items" :key="item">{{ item }}</li>
            </ul>
          </article>
        </div>
      </div>
    </section>

    <section class="section section--alt">
      <div class="container container--narrow prose">
        <SectionHeading
          title="Who we build for"
          subtitle="Ideal for EU-based teams with predictable document and inference volume, async workloads, and a need for region-aware execution."
          align="left"
        />
        <ul class="check-list">
          <li>Document processing &amp; fintech operations</li>
          <li>Contact centers and compliance review teams</li>
          <li>Marketplaces needing moderation at scale</li>
          <li>AI product teams validating model output quality</li>
          <li>Enterprises requiring audit trails for every inference</li>
        </ul>
      </div>
    </section>

    <CtaBand
      title="Not sure which task type fits?"
      body="We will map your workflow to the catalog, verification tier, and execution policy that match your SLA and budget."
    />
  </div>
</template>
