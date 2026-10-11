<script setup>
const icons = {
  grid: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
  tasks: 'M8 4h11v17H5V4h3 M8 2h8v4H8z M8 11h8 M8 15h6',
  chart: 'M4 20V10 M10 20V4 M16 20v-8 M22 20H2',
  wallet: 'M3 5h17v15H3z M3 5l14-3v3 M15 11h7v5h-7z',
  key: 'M14 3a5 5 0 1 0 0 10a5 5 0 0 0 0-10 M10 12L3 19v3h3v-3h3v-3',
  file: 'M5 2h9l5 5v15H5z M14 2v6h5 M8 12h8 M8 16h6',
  team: 'M9 3a3 3 0 1 0 0 6a3 3 0 0 0 0-6 M2 20v-3a6 6 0 0 1 12 0v3 M16 4a3 3 0 0 1 0 6 M17 13a5 5 0 0 1 5 5v2',
  plus: 'M12 4v16 M4 12h16',
  logout: 'M9 4H3v16h6 M10 12h11 M16 7l5 5-5 5',
  menu: 'M3 5h18 M3 12h18 M3 19h18',
  close: 'M5 5l14 14 M5 19L19 5',
  spark: 'M12 2l3 7 7 3-7 3-3 7-3-7-7-3 7-3z',
  check: 'M4 12l5 5L20 5',
  alert: 'M12 2l10 19H2z M12 9v5 M12 17v1',
  clock: 'M12 2a10 10 0 1 0 0 20a10 10 0 0 0 0-20 M12 6v6l4 3',
  lock: 'M6 11h12v11H6z M8 11V6a4 4 0 0 1 8 0v5',
  search: 'M10 3a7 7 0 1 0 0 14a7 7 0 0 0 0-14 M16 16l5 5',
  more: 'M4 12h1 M11 12h1 M18 12h1',
  arrow: 'M4 12h15 M14 7l5 5-5 5',
  upload: 'M12 16V3 M7 8l5-5 5 5 M3 16v5h18v-5',
  download: 'M12 2v13 M7 10l5 5 5-5 M3 16v5h18v-5',
};

defineProps({
  name: { type: String, default: 'grid' },
});
</script>

<template>
  <svg class="fn-icon" viewBox="0 0 24 24" aria-hidden="true">
    <path :d="icons[name] || icons.grid" />
  </svg>
</template>
