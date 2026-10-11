<script setup>
import { RouterLink } from 'vue-router';

import { useSession } from '../auth/session';
import StrokeIcon from '../components/ui/StrokeIcon.vue';
import { t } from '../i18n';

const session = useSession();

const menuSections = [
  {
    titleKey: 'more.integrations',
    items: [
      { name: 'api-keys', labelKey: 'nav.apiKeys', icon: 'key', permission: 'customer.apikeys:read' },
    ],
  },
  {
    titleKey: 'more.workspace',
    items: [
      { name: 'files', labelKey: 'nav.files', icon: 'file', permission: 'customer.tasks:read' },
      { name: 'wallet', labelKey: 'nav.wallet', icon: 'wallet', permission: 'customer.billing:read' },
      { name: 'account', labelKey: 'nav.account', icon: 'team', permission: null },
    ],
  },
];

const visibleSections = menuSections
  .map((section) => ({
    ...section,
    items: section.items.filter(
      (item) => item.permission === null || session.hasPermission(item.permission),
    ),
  }))
  .filter((section) => section.items.length);
</script>

<template>
  <section class="em-page">
    <div class="fn-tilegrid">
      <template v-for="section in visibleSections" :key="section.titleKey">
        <RouterLink
          v-for="item in section.items"
          :key="item.name"
          :to="{ name: item.name }"
          class="md-card fn-tile"
        >
          <span class="fn-tile__icon" aria-hidden="true"><StrokeIcon :name="item.icon" /></span>
          <h2>{{ t(item.labelKey) }}</h2>
          <p>{{ t(section.titleKey) }}</p>
        </RouterLink>
      </template>
    </div>
  </section>
</template>
