<script setup>
import CtaBand from '../components/CtaBand.vue';
import { workerPoints } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Workers</p>
        <h1 class="page-hero__title">Contribute compute on your terms</h1>
        <p class="page-hero__lead">
          The EdgeMint Worker app runs assigned AI tasks on your device when you opt in. This is on-device inference —
          not cryptocurrency mining — with transparent, variable EUR rewards.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container container--narrow">
        <div class="disclosure-card">
          <h2>Important disclosures</h2>
          <ul class="check-list">
            <li v-for="point in workerPoints" :key="point">{{ point }}</li>
          </ul>
        </div>
      </div>
    </section>

    <section class="section section--alt">
      <div class="container container--narrow prose">
        <h2>How assignment works</h2>
        <p>
          When your availability toggle is on, EdgeMint assigns tasks that match your device tier and installed models.
          You do not accept or reject individual tasks — availability is the control. Rewards move through estimated,
          pending, and verified states before payout.
        </p>
        <h2>Your device, your controls</h2>
        <p>
          Configure Wi-Fi-only downloads, battery thresholds, and thermal limits. A foreground indicator shows when a
          task is actively running. Models are signed and verified before execution.
        </p>
      </div>
    </section>

    <CtaBand
      title="Interested in the worker program?"
      body="Worker enrollment is rolling out by region. Contact us to join the waitlist or receive the Android build."
      cta-label="Join waitlist"
    />
  </div>
</template>
