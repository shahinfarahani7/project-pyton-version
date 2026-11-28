<script setup>
import { onMounted, ref } from 'vue';

import { opsApi } from '../api/client';
import { useSession } from '../auth/session';

const session = useSession();
const items = ref([]);
const roles = ref([]);
const email = ref('');
const role = ref('operator.approver');
const error = ref('');
const status = ref('');
const loading = ref(false);

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const body = await opsApi.listAdmins();
    items.value = body.items ?? [];
    roles.value = body.roles ?? [];
    if (!roles.value.includes(role.value) && roles.value.length) {
      role.value = roles.value.includes('operator.approver')
        ? 'operator.approver'
        : roles.value[0];
    }
  } catch (err) {
    error.value = err.message;
  } finally {
    loading.value = false;
  }
}

async function addAdmin() {
  status.value = '';
  error.value = '';
  try {
    await opsApi.addAdmin({ email: email.value, role: role.value });
    email.value = '';
    status.value = 'Admin access granted.';
    await load();
  } catch (err) {
    error.value = err.message;
  }
}

async function removeAdmin(targetEmail) {
  status.value = '';
  error.value = '';
  try {
    await opsApi.removeAdmin(targetEmail);
    status.value = `Removed ${targetEmail}.`;
    await load();
  } catch (err) {
    error.value = err.message;
  }
}

onMounted(load);
</script>

<template>
  <section v-if="!session.hasPermission('operations.read')" class="panel">
    <p>Read permission required.</p>
  </section>
  <section v-else class="panel">
    <div class="page-header">
      <h1>Admin access</h1>
      <p class="muted">Emails that can open the operations console after portal sign-in.</p>
      <button type="button" class="ghost" :disabled="loading" @click="load">Refresh</button>
    </div>

    <p v-if="error" class="alert" role="alert">{{ error }}</p>
    <p v-if="status" role="status">{{ status }}</p>

    <form
      v-if="session.hasPermission('operations.approve')"
      class="admin-form"
      @submit.prevent="addAdmin"
    >
      <label>
        Email
        <input v-model="email" type="email" autocomplete="off" required placeholder="name@company.com" />
      </label>
      <label>
        Role
        <select v-model="role">
          <option v-for="option in roles" :key="option" :value="option">{{ option }}</option>
        </select>
      </label>
      <button type="submit">Add admin</button>
    </form>
    <p v-else class="muted">Approver permission is required to add or remove admins.</p>

    <div class="table-wrap">
      <table data-table="admins">
        <thead>
          <tr>
            <th scope="col">Email</th>
            <th scope="col">Role</th>
            <th scope="col">Source</th>
            <th scope="col"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!items.length">
            <td colspan="4" class="muted">No admin emails configured.</td>
          </tr>
          <tr v-for="item in items" :key="item.email">
            <td class="mono">{{ item.email }}</td>
            <td>{{ item.role }}</td>
            <td>
              <span v-if="item.source === 'environment'">Environment</span>
              <span v-else>Managed</span>
              <small v-if="item.overridesEnvironment" class="muted"> · overrides env</small>
            </td>
            <td>
              <button
                v-if="item.editable && session.hasPermission('operations.approve')"
                type="button"
                class="ghost"
                :disabled="item.email === session.operatorId"
                @click="removeAdmin(item.email)"
              >
                Remove
              </button>
              <span v-else-if="item.source === 'environment'" class="muted">Read-only</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.admin-form {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  align-items: end;
  margin: 1rem 0 1.5rem;
}

.admin-form label {
  display: grid;
  gap: 0.35rem;
  min-width: 14rem;
}

.admin-form input,
.admin-form select {
  min-height: 2.4rem;
}
</style>
