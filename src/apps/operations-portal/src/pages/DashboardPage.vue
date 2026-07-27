<script setup>
import { useSession } from '../auth/session';

const session = useSession();
</script>

<template>
  <section class="panel">
    <h1>Operations overview</h1>
    <p>Least-privilege operator session with SSO/MFA and audited administrative actions.</p>
    <dl>
      <dt>Operator</dt>
      <dd>{{ session.operatorId }}</dd>
      <dt>Role</dt>
      <dd>{{ session.role }}</dd>
    </dl>
  </section>
</template>
