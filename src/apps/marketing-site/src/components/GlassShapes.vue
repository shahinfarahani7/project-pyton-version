<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';

const root = ref(null);
const canvas = ref(null);
const ready = ref(false);

let scene = null;
let observer = null;
let resizeObserver = null;
let disposed = false;
let booting = false;
let visible = false;

function onPointerMove(event) {
  if (!scene || !root.value) return;
  const rect = root.value.getBoundingClientRect();
  const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  const y = ((event.clientY - rect.top) / rect.height) * 2 - 1;
  scene.setPointer(Math.max(-1, Math.min(1, x)), Math.max(-1, Math.min(1, y)));
}

function onPointerLeave() {
  scene?.setPointer(0, 0);
}

async function boot() {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  try {
    const { createGlassScene } = await import('./glassScene.js');
    if (disposed || !canvas.value) return;
    scene = createGlassScene(canvas.value, { reducedMotion });
    ready.value = true;
    if (visible) scene.start();
    resizeObserver = new ResizeObserver(() => scene?.resize());
    resizeObserver.observe(canvas.value);
  } catch {
    scene = null;
    ready.value = false;
  }
}

onMounted(() => {
  observer = new IntersectionObserver((entries) => {
    visible = entries.some((entry) => entry.isIntersecting);
    if (visible && !scene && !booting) {
      booting = true;
      boot();
    } else if (scene) {
      if (visible) scene.start();
      else scene.stop();
    }
  }, { rootMargin: '200px 0px' });
  observer.observe(root.value);
});

onBeforeUnmount(() => {
  disposed = true;
  observer?.disconnect();
  resizeObserver?.disconnect();
  scene?.dispose();
  scene = null;
});
</script>

<template>
  <div
    ref="root"
    class="em-glass"
    :class="{ 'is-3d': ready }"
    aria-hidden="true"
    @pointermove="onPointerMove"
    @pointerleave="onPointerLeave"
  >
    <canvas ref="canvas" class="em-glass__canvas"></canvas>
    <span class="em-glass__cone"></span>
    <span class="em-glass__torus"></span>
    <span class="em-glass__cube"></span>
  </div>
</template>
