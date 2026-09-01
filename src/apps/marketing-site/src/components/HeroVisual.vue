<script setup>
const nodes = [
  { id: 'portal', label: 'Portal / API', icon: '⬡', x: 8, y: 42 },
  { id: 'quote', label: 'Quote', icon: '€', x: 32, y: 18 },
  { id: 'edge', label: 'Edge worker', icon: '◈', x: 58, y: 48 },
  { id: 'verify', label: 'Verify', icon: '⛨', x: 82, y: 22 },
  { id: 'result', label: 'Result', icon: '✓', x: 92, y: 62 },
];
</script>

<template>
  <div class="hero-visual" aria-hidden="true">
    <div class="hero-visual__frame">
      <div class="hero-visual__scanline" />
      <svg class="hero-visual__svg" viewBox="0 0 400 220">
        <defs>
          <linearGradient id="pipe-grad" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stop-color="#7c4dff" />
            <stop offset="50%" stop-color="#22d3ee" />
            <stop offset="100%" stop-color="#6ee7b7" />
          </linearGradient>
        </defs>
        <path
          class="hero-visual__path"
          d="M40,92 C100,92 120,40 160,40 C200,40 220,100 260,100 C300,100 320,50 360,50"
        />
        <path
          class="hero-visual__path hero-visual__path--ghost"
          d="M40,92 C100,92 120,40 160,40 C200,40 220,100 260,100 C300,100 320,50 360,50"
        />
        <circle class="hero-visual__pulse hero-visual__pulse--1" r="5" cx="40" cy="92" />
        <circle class="hero-visual__pulse hero-visual__pulse--2" r="5" cx="160" cy="40" />
        <circle class="hero-visual__pulse hero-visual__pulse--3" r="5" cx="260" cy="100" />
        <circle class="hero-visual__pulse hero-visual__pulse--4" r="5" cx="360" cy="50" />
      </svg>

      <div
        v-for="node in nodes"
        :key="node.id"
        class="hero-visual__node"
        :style="{ left: `${node.x}%`, top: `${node.y}%` }"
      >
        <span class="hero-visual__node-icon">{{ node.icon }}</span>
        <span class="hero-visual__node-label">{{ node.label }}</span>
      </div>

      <div class="hero-visual__metrics">
        <div class="hero-visual__metric">
          <span class="hero-visual__metric-label">Latency</span>
          <strong>842ms</strong>
        </div>
        <div class="hero-visual__metric">
          <span class="hero-visual__metric-label">Route</span>
          <strong>edge</strong>
        </div>
        <div class="hero-visual__metric hero-visual__metric--live">
          <span class="hero-visual__live-dot" />
          Live stream
        </div>
      </div>
    </div>

    <div class="hero-visual__orbit hero-visual__orbit--1" />
    <div class="hero-visual__orbit hero-visual__orbit--2" />
  </div>
</template>
