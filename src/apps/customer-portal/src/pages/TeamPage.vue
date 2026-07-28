<script setup>
import PageHeader from '../components/ui/PageHeader.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { t } from '../i18n';

const members = [
  { name: 'Dev User', email: 'dev-user@edgemint.local', role: 'Owner', status: 'active' },
  { name: 'Pipeline Bot', email: 'ci@edgemint.local', role: 'Developer', status: 'active' },
  { name: 'Finance Lead', email: 'billing@edgemint.local', role: 'Billing', status: 'active' },
];

const roles = [
  { name: 'Owner', permissions: ['customer.*'] },
  { name: 'Developer', permissions: ['customer.tasks:*', 'customer.webhooks:read'] },
  { name: 'Billing', permissions: ['customer.billing:read'] },
];
</script>

<template>
  <section>
    <PageHeader :title="t('nav.team')" :subtitle="t('team.subtitle')">
      <template #actions>
        <button type="button" class="md-btn md-btn-filled" disabled>
          <span class="material-symbols-outlined" aria-hidden="true">person_add</span>
          {{ t('team.invite') }}
        </button>
      </template>
    </PageHeader>

    <article class="md-card">
      <PageHeader :title="t('team.membersTitle')" />
      <div class="md-table-wrap">
        <table class="md-table">
          <thead>
            <tr>
              <th scope="col">{{ t('team.member') }}</th>
              <th scope="col">{{ t('team.role') }}</th>
              <th scope="col">{{ t('billing.status') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="member in members" :key="member.email">
              <td>
                <div style="display: flex; align-items: center; gap: 0.75rem">
                  <span class="avatar" aria-hidden="true">{{ member.name.slice(0, 1) }}</span>
                  <div>
                    <div>{{ member.name }}</div>
                    <div class="page-subtitle">{{ member.email }}</div>
                  </div>
                </div>
              </td>
              <td>{{ member.role }}</td>
              <td><StatusChip :status="member.status" /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>

    <article class="md-card">
      <PageHeader :title="t('team.rolesTitle')" :subtitle="t('team.rolesSubtitle')" />
      <div class="md-table-wrap">
        <table class="md-table">
          <thead>
            <tr>
              <th scope="col">{{ t('team.role') }}</th>
              <th scope="col">{{ t('team.permissions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="role in roles" :key="role.name">
              <td>{{ role.name }}</td>
              <td>
                <div class="permission-list">
                  <StatusChip v-for="permission in role.permissions" :key="permission" :status="permission" />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </section>
</template>
