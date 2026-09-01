<script setup>
import { portalLoginUrl } from '../config/env.js';
import { contactChannels } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Contact</p>
        <h1 class="page-hero__title">Talk to the EdgeMint team</h1>
        <p class="page-hero__lead">
          Request an enterprise demo, ask about pricing and regions, or get help integrating the task API into your
          product.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container contact-grid">
        <form class="contact-form" @submit.prevent>
          <label>
            <span>Full name</span>
            <input type="text" name="name" autocomplete="name" placeholder="Your name" />
          </label>
          <label>
            <span>Work email</span>
            <input type="email" name="email" autocomplete="email" placeholder="you@company.com" />
          </label>
          <label>
            <span>Company</span>
            <input type="text" name="company" autocomplete="organization" placeholder="Company name" />
          </label>
          <label>
            <span>How can we help?</span>
            <textarea name="message" rows="5" placeholder="Tell us about your workload, volume, and timeline." />
          </label>
          <button type="submit" class="btn btn--primary btn--lg" disabled>
            Send message (coming soon)
          </button>
          <p class="contact-form__hint">Form backend not wired in this preview — use the channels below.</p>
        </form>

        <aside class="contact-aside">
          <h2>Direct channels</h2>
          <ul class="contact-channels">
            <li v-for="channel in contactChannels" :key="channel.label">
              <span>{{ channel.label }}</span>
              <a :href="`mailto:${channel.value}`">{{ channel.value }}</a>
            </li>
          </ul>
          <div class="contact-aside__card">
            <h3>Customer portal</h3>
            <p>Already have access? Sign in to create and monitor tasks.</p>
            <a class="btn btn--outline btn--block" :href="portalLoginUrl">Open portal</a>
          </div>
        </aside>
      </div>
    </section>
  </div>
</template>
