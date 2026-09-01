<script setup>
import { statusComponents } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">System status</p>
        <h1 class="page-hero__title">Platform health overview</h1>
        <p class="page-hero__lead">
          Production status is published from a dedicated monitoring stack. This preview shows the components that make
          up the EdgeMint platform.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container container--narrow">
        <div class="status-banner status-banner--ok">
          <span class="status-banner__dot" aria-hidden="true" />
          <div>
            <strong>All systems operational</strong>
            <p>Development preview — connect production status feed for live incident updates.</p>
          </div>
        </div>

        <table class="pricing-table status-table">
          <thead>
            <tr>
              <th scope="col">Component</th>
              <th scope="col">Role</th>
              <th scope="col">Status</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in statusComponents" :key="row.name">
              <td>{{ row.name }}</td>
              <td>{{ row.role }}</td>
              <td><span class="status-pill status-pill--ok">{{ row.status }}</span></td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
