<script setup>
import CtaBand from '../components/CtaBand.vue';
import { developerPoints } from '../content/site.js';
</script>

<template>
  <div class="page">
    <section class="page-hero">
      <div class="container container--narrow">
        <p class="page-hero__eyebrow">Developers</p>
        <h1 class="page-hero__title">Integrate async AI tasks into your product</h1>
        <p class="page-hero__lead">
          Submit workloads through the REST API or customer portal, receive webhooks on lifecycle changes, and inspect
          structured results — with idempotent creates and typed OpenAPI contracts.
        </p>
      </div>
    </section>

    <section class="section">
      <div class="container">
        <div class="code-showcase">
          <pre><code>POST /v1/workspaces/{workspaceId}/tasks
{
  "taskType": "document.ocr",
  "inputText": "Invoice #INV-2026-0847…",
  "instructions": "Extract total and vendor name"
}

→ 201 Created · quote €0.0025 · edge-preferred
→ webhook: task.updated · lifecycle=succeeded</code></pre>
        </div>
      </div>
    </section>

    <section class="section section--alt">
      <div class="container container--narrow">
        <ul class="check-list check-list--large">
          <li v-for="point in developerPoints" :key="point">{{ point }}</li>
        </ul>
      </div>
    </section>

    <section class="section">
      <div class="container container--narrow prose">
        <h2>Local development</h2>
        <p>
          Run the Docker backend and customer portal locally. Use <strong>Dev sign-in</strong> to create tasks, subscribe
          to live SSE events, and validate end-to-end worker execution on a physical device or emulator.
        </p>
        <pre class="inline-code-block"><code>npm run dev --prefix src/apps/customer-portal
# Portal → http://127.0.0.1:5173</code></pre>
      </div>
    </section>

    <CtaBand
      title="Request production API access"
      body="We will provision workspace credentials, webhook endpoints, and the integration guide for your environment."
      cta-label="Talk to developers"
    />
  </div>
</template>
