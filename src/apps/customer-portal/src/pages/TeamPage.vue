<script setup>
import { t } from '../i18n';

const roles = [
  { name: 'Owner', permissions: ['customer.*'] },
  { name: 'Developer', permissions: ['customer.tasks:*', 'customer.webhooks:read'] },
  { name: 'Billing', permissions: ['customer.billing:read'] },
];
</script>

<template>
  <section class="panel">
    <h1>{{ t('nav.team') }}</h1>
    <p>Workspace RBAC is enforced server-side; the portal only renders actions allowed by the active session.</p>
    <table>
      <thead>
        <tr>
          <th scope="col">Role</th>
          <th scope="col">Permissions</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="role in roles" :key="role.name">
          <td>{{ role.name }}</td>
          <td>{{ role.permissions.join(', ') }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
