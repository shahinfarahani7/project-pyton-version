<script setup>
import { useSession } from '../auth/session';
import { t } from '../i18n';
import { trackEvent } from '../telemetry';

const session = useSession();

function onWorkspaceChange(event) {
  const next = event.target.value;
  trackEvent('portal.workspace.switch', { workspaceId: next });
  void session.switchWorkspace(next);
}
</script>

<template>
  <label v-if="session.workspaces.length > 0" class="workspace-switcher md-field">
    <span class="visually-hidden">{{ t('workspace.switch') }}</span>
    <select
      class="md-select"
      :aria-label="t('workspace.switch')"
      :value="session.workspaceId ?? ''"
      @change="onWorkspaceChange"
    >
      <option v-for="workspace in session.workspaces" :key="workspace.id" :value="workspace.id">
        {{ workspace.name }}
      </option>
    </select>
  </label>
</template>
