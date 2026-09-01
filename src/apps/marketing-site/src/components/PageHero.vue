<script setup>
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  lead: { type: String, default: '' },
  badges: { type: Array, default: () => [] },
});
</script>

<template>
  <section class="page-hero">
    <div class="page-hero__decor" aria-hidden="true">
      <span class="page-hero__corner page-hero__corner--tl" />
      <span class="page-hero__corner page-hero__corner--tr" />
      <span class="page-hero__corner page-hero__corner--bl" />
      <span class="page-hero__corner page-hero__corner--br" />
      <span class="page-hero__ring" />
      <span v-for="(badge, index) in badges" :key="badge" class="page-hero__float" :style="{ '--fi': index }">
        {{ badge }}
      </span>
    </div>
    <div class="container container--narrow page-hero__content">
      <p v-if="eyebrow" class="page-hero__eyebrow reveal is-visible">{{ eyebrow }}</p>
      <h1 class="page-hero__title reveal is-visible" style="--reveal-delay: 80ms">{{ title }}</h1>
      <p v-if="lead" class="page-hero__lead reveal is-visible" style="--reveal-delay: 160ms">{{ lead }}</p>
      <slot />
    </div>
  </section>
</template>
