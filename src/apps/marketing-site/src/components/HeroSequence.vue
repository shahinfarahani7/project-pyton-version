<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';

import BrandMark from './BrandMark.vue';
import BrandWordmark from './BrandWordmark.vue';

const MANIFEST_URL = '/hero-sequence/manifest.json';
const VIDEO_END = 0.84;

const root = ref(null);
const canvas = ref(null);
const ready = ref(false);
const reduced = ref(false);
const progress = ref(0);

const beats = [
  { from: 0.2, to: 0.42, eyebrow: '01 · Edge network', title: 'Opted-in phones run signed models.' },
  { from: 0.42, to: 0.66, eyebrow: '02 · Verified results', title: 'Every result flows back and is checked.' },
];
const activeBeat = computed(() => beats.findIndex((beat) => progress.value >= beat.from && progress.value < beat.to));
const markReveal = computed(() => Math.min(1, Math.max(0, (progress.value - 0.78) / 0.14)));

let sequence = null;
let frames = [];
let drawnIndex = -1;
let shown = 0;
let target = 0;
let loop = 0;
let visible = false;
let disposed = false;
let observer = null;
let resizeObserver = null;
let scrollFrame = 0;

function framePath(set, index) {
  return set.path.replace('{i}', String(index + 1).padStart(set.pad ?? 4, '0'));
}

function pickSet(manifest) {
  const portrait = window.innerWidth / window.innerHeight < 0.8;
  return (portrait && manifest.mobile) || manifest.desktop;
}

function loadOrder(count) {
  const order = [];
  const seen = new Set();
  for (let stride = 16; stride >= 1; stride /= 2) {
    for (let i = 0; i < count; i += stride) {
      if (!seen.has(i)) {
        seen.add(i);
        order.push(i);
      }
    }
  }
  if (!seen.has(count - 1)) order.push(count - 1);
  return order;
}

function loadFrames(set) {
  frames = new Array(set.count).fill(null);
  const order = loadOrder(set.count);
  let cursor = 0;
  const next = () => {
    if (disposed || cursor >= order.length) return;
    const index = order[cursor];
    cursor += 1;
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => {
      frames[index] = image;
      if (index === 0) {
        ready.value = true;
        resize();
      }
      drawnIndex = -1;
      next();
    };
    image.onerror = next;
    image.src = framePath(set, index);
  };
  for (let lane = 0; lane < 4; lane += 1) next();
}

function nearestLoaded(index) {
  for (let offset = 0; offset < frames.length; offset += 1) {
    if (frames[index - offset]) return index - offset;
    if (frames[index + offset]) return index + offset;
  }
  return -1;
}

function draw() {
  if (!sequence || !canvas.value) return;
  const wanted = Math.round(Math.min(1, shown / VIDEO_END) * (sequence.count - 1));
  const index = nearestLoaded(wanted);
  if (index < 0 || index === drawnIndex) return;
  const image = frames[index];
  const ctx = canvas.value.getContext('2d');
  const { width, height } = canvas.value;
  const scale = Math.max(width / image.naturalWidth, height / image.naturalHeight);
  const w = image.naturalWidth * scale;
  const h = image.naturalHeight * scale;
  ctx.drawImage(image, (width - w) / 2, (height - h) / 2, w, h);
  drawnIndex = index;
}

function resize() {
  if (!canvas.value) return;
  const rect = canvas.value.getBoundingClientRect();
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  canvas.value.width = Math.max(1, Math.round(rect.width * ratio));
  canvas.value.height = Math.max(1, Math.round(rect.height * ratio));
  drawnIndex = -1;
  draw();
}

function tick() {
  loop = 0;
  shown += (target - shown) * 0.18;
  if (Math.abs(target - shown) < 0.0005) shown = target;
  draw();
  if (visible && shown !== target) loop = requestAnimationFrame(tick);
}

function measure() {
  scrollFrame = 0;
  if (!root.value) return;
  const rect = root.value.getBoundingClientRect();
  const runway = rect.height - window.innerHeight;
  target = runway > 0 ? Math.min(1, Math.max(0, -rect.top / runway)) : 0;
  progress.value = target;
  if (reduced.value) {
    shown = target;
    draw();
  } else if (visible && !loop) {
    loop = requestAnimationFrame(tick);
  }
}

function onScroll() {
  if (!scrollFrame) scrollFrame = requestAnimationFrame(measure);
}

async function boot() {
  try {
    const response = await fetch(MANIFEST_URL, { cache: 'no-cache' });
    if (!response.ok || !(response.headers.get('content-type') || '').includes('json')) return;
    const set = pickSet(await response.json());
    if (disposed || !set?.count || !set?.path) return;
    sequence = set;
    loadFrames(set);
  } catch {
    sequence = null;
  }
}

onMounted(() => {
  reduced.value = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll, { passive: true });
  observer = new IntersectionObserver((entries) => {
    visible = entries.some((entry) => entry.isIntersecting);
    if (visible) measure();
  });
  observer.observe(root.value);
  resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(canvas.value);
  measure();
  boot();
});

onBeforeUnmount(() => {
  disposed = true;
  window.removeEventListener('scroll', onScroll);
  window.removeEventListener('resize', onScroll);
  cancelAnimationFrame(scrollFrame);
  cancelAnimationFrame(loop);
  observer?.disconnect();
  resizeObserver?.disconnect();
  frames = [];
});
</script>

<template>
  <div ref="root" class="em-story" :class="{ 'is-ready': ready, 'is-static': reduced || !ready }">
    <div class="em-story__stage" aria-hidden="true">
      <canvas ref="canvas" class="em-story__canvas"></canvas>
      <div class="em-story__mark" :style="{ '--reveal': markReveal }">
        <BrandMark :size="168" />
      </div>
      <div class="em-story__captions">
        <p
          v-for="(beat, index) in beats"
          :key="beat.eyebrow"
          class="em-story__caption"
          :class="{ 'is-on': ready && !reduced && activeBeat === index }"
        >
          <span class="em-story__eyebrow">{{ beat.eyebrow }}</span>
          <span class="em-story__title">{{ beat.title }}</span>
        </p>
        <p class="em-story__caption em-story__caption--brand" :class="{ 'is-on': ready && !reduced && markReveal > 0.6 }">
          <span class="em-story__eyebrow">03 · Many devices, one platform</span>
          <span class="em-story__title">Together, they build <BrandWordmark /></span>
        </p>
      </div>
    </div>
    <slot />
  </div>
</template>
