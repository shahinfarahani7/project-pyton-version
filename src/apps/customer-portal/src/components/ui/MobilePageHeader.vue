<script setup>
import { computed } from 'vue';
import { RouterLink, useRouter } from 'vue-router';

import { useSession } from '../../auth/session';

const props = defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  showBack: { type: Boolean, default: false },
  backTo: { type: [String, Object], default: null },
});

const emit = defineEmits(['menu']);

const session = useSession();
const router = useRouter();

const avatarLetter = computed(() => {
  const name = session.workspaces.find((w) => w.id === session.workspaceId)?.name ?? 'E';
  return name.charAt(0).toUpperCase();
});

function onBack() {
  if (props.backTo) {
    void router.push(props.backTo);
  }
}
</script>

<template>
  <header class="em-page-header">
    <div class="em-page-header__start">
      <button
        v-if="showBack"
        type="button"
        class="em-icon-btn"
        :aria-label="title"
        @click="onBack"
      >
        <span class="material-symbols-outlined" aria-hidden="true">arrow_back</span>
      </button>
      <RouterLink v-else-if="showBack === false && backTo" class="em-icon-btn" :to="backTo">
        <span class="material-symbols-outlined" aria-hidden="true">arrow_back</span>
      </RouterLink>
      <button v-else type="button" class="em-icon-btn" aria-label="Menu" @click="emit('menu')">
        <span class="material-symbols-outlined" aria-hidden="true">menu</span>
      </button>
    </div>
    <div class="em-page-header__titles">
      <h1 class="em-page-header__title">{{ title }}</h1>
      <p v-if="subtitle" class="em-page-header__subtitle">{{ subtitle }}</p>
    </div>
    <div class="em-page-header__avatar avatar" aria-hidden="true">{{ avatarLetter }}</div>
  </header>
</template>
