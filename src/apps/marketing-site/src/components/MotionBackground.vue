<script setup>
import { onMounted, onUnmounted, ref } from 'vue';

const root = ref(null);
let raf = 0;

function update() {
  if (!root.value) return;

  const scrollY = window.scrollY;
  const maxScroll = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
  const progress = scrollY / maxScroll;

  root.value.style.setProperty('--scroll-y', String(scrollY));
  root.value.style.setProperty('--scroll-progress', String(progress));
}

function onScroll() {
  cancelAnimationFrame(raf);
  raf = requestAnimationFrame(update);
}

onMounted(() => {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  update();
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll, { passive: true });
});

onUnmounted(() => {
  window.removeEventListener('scroll', onScroll);
  window.removeEventListener('resize', onScroll);
  cancelAnimationFrame(raf);
});
</script>

<template>
  <div ref="root" class="motion-bg" aria-hidden="true">
    <div class="motion-bg__noise" />
    <div class="motion-bg__vignette" />

    <div class="motion-bg__layer motion-bg__layer--aurora">
      <div class="motion-bg__aurora motion-bg__aurora--a" />
      <div class="motion-bg__aurora motion-bg__aurora--b" />
    </div>

    <div class="motion-bg__layer motion-bg__layer--orbs">
      <div class="motion-bg__orb motion-bg__orb--violet" />
      <div class="motion-bg__orb motion-bg__orb--cyan" />
      <div class="motion-bg__orb motion-bg__orb--indigo" />
      <div class="motion-bg__orb motion-bg__orb--rose" />
    </div>

    <div class="motion-bg__layer motion-bg__layer--rings">
      <div class="motion-bg__ring motion-bg__ring--1" />
      <div class="motion-bg__ring motion-bg__ring--2" />
      <div class="motion-bg__ring motion-bg__ring--3" />
    </div>

    <div class="motion-bg__layer motion-bg__layer--grid">
      <div class="motion-bg__grid" />
      <div class="motion-bg__grid motion-bg__grid--fine" />
    </div>

    <svg class="motion-bg__mesh" viewBox="0 0 1200 800" preserveAspectRatio="xMidYMid slice">
      <defs>
        <linearGradient id="mesh-grad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="rgba(124,77,255,0.5)" />
          <stop offset="100%" stop-color="rgba(34,211,238,0.35)" />
        </linearGradient>
      </defs>
      <path class="motion-bg__mesh-line" d="M120,180 Q420,80 680,220 T1080,160" />
      <path class="motion-bg__mesh-line" d="M80,420 Q360,320 620,460 T1120,380" />
      <path class="motion-bg__mesh-line" d="M200,620 Q500,520 760,640 T1100,560" />
      <circle class="motion-bg__mesh-dot" cx="120" cy="180" r="4" />
      <circle class="motion-bg__mesh-dot" cx="680" cy="220" r="4" />
      <circle class="motion-bg__mesh-dot" cx="1080" cy="160" r="4" />
      <circle class="motion-bg__mesh-dot" cx="620" cy="460" r="4" />
      <circle class="motion-bg__mesh-dot" cx="760" cy="640" r="4" />
    </svg>

    <div class="motion-bg__layer motion-bg__layer--beams">
      <div class="motion-bg__beam motion-bg__beam--1" />
      <div class="motion-bg__beam motion-bg__beam--2" />
    </div>

    <div class="motion-bg__layer motion-bg__layer--particles">
      <span v-for="n in 18" :key="n" class="motion-bg__particle" :style="{ '--i': n }" />
    </div>

    <div class="motion-bg__layer motion-bg__layer--nodes">
      <span v-for="n in 10" :key="n" class="motion-bg__node" :style="{ '--i': n }" />
    </div>
  </div>
</template>
