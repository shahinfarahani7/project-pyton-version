<script setup>
import { computed, ref } from 'vue';
import { portalApi } from '../api/client';
import { useSession } from '../auth/session';
import { useAsyncResource } from '../composables/useAsyncResource';
import ApiKeyUsageGuide from '../components/ApiKeyUsageGuide.vue';
import ApiKeyUsagePanel from '../components/ApiKeyUsagePanel.vue';
import EmptyState from '../components/ui/EmptyState.vue';
import StatusChip from '../components/ui/StatusChip.vue';
import { resolveLocale, t } from '../i18n';

const session = useSession();
const canRead = computed(() => session.hasPermission('customer.apikeys:read') || session.hasPermission('customer.api-keys:read'));
const canWrite = computed(() => session.hasPermission('customer.api-keys:write'));

const { data: items, error, loading, refresh } = useAsyncResource(() => portalApi.apiKeys(), {
  enabled: () => canRead.value,
});

const keys = computed(() => items.value?.items ?? []);
const activeCount = computed(() => keys.value.filter((item) => item.status === 'active').length);

const formOpen = ref(false);
const keyName = ref('');
const allowRead = ref(true);
const allowWrite = ref(true);
const expiresDays = ref('');
const cidrs = ref('');
const creating = ref(false);
const createError = ref('');
const revealedSecret = ref('');
const revealedKeyId = ref('');
const copied = ref(false);
const pending = ref(null);
const busyKeyId = ref('');

const dateLocale = resolveLocale() === 'fa' ? 'fa-IR' : 'en-US';

function formatDate(iso) {
  return iso ? new Date(iso).toLocaleDateString(dateLocale, { year: 'numeric', month: 'short', day: 'numeric' }) : '';
}

function maskedKey(item) {
  return item.prefix ? `${item.prefix}${'•'.repeat(12)}` : `${item.id.slice(0, 8)}••••••••`;
}

function scopeLabel(scope) {
  if (scope === 'customer.tasks:read') {
    return t('apiKeys.scopeRead');
  }
  if (scope === 'customer.tasks:write') {
    return t('apiKeys.scopeWrite');
  }
  return scope;
}

function newIdempotencyKey() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  return `idem-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function selectedScopes() {
  const scopes = [];
  if (allowRead.value) {
    scopes.push('customer.tasks:read');
  }
  if (allowWrite.value) {
    scopes.push('customer.tasks:write');
  }
  return scopes;
}

function openForm() {
  createError.value = '';
  formOpen.value = true;
}

function closeForm() {
  formOpen.value = false;
  createError.value = '';
}

async function createKey() {
  const name = keyName.value.trim();
  const scopes = selectedScopes();
  const days = expiresDays.value === '' ? null : Number(expiresDays.value);
  if (!name || !scopes.length || !canWrite.value || (days !== null && (!Number.isInteger(days) || days < 1 || days > 366))) {
    createError.value = t('apiKeys.createError');
    return;
  }
  creating.value = true;
  createError.value = '';
  copied.value = false;
  const body = {
    name,
    scopes,
    allowedCidrs: cidrs.value.split(/[\s,]+/).map((item) => item.trim()).filter(Boolean),
  };
  if (days !== null) {
    body.expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }
  try {
    showSecret(await portalApi.createApiKey(body, newIdempotencyKey()));
    keyName.value = '';
    cidrs.value = '';
    expiresDays.value = '';
    formOpen.value = false;
    await refresh({ silent: true });
  } catch (err) {
    createError.value = err?.message || t('apiKeys.createError');
  } finally {
    creating.value = false;
  }
}

async function copySecret() {
  if (!revealedSecret.value) {
    return;
  }
  try {
    await navigator.clipboard.writeText(revealedSecret.value);
    copied.value = true;
  } catch {
    copied.value = false;
  }
}

function dismissSecret() {
  revealedSecret.value = '';
  revealedKeyId.value = '';
  copied.value = false;
}

function showSecret(body) {
  revealedSecret.value = body.secret ?? '';
  revealedKeyId.value = body.id ?? body.resourceId ?? '';
  copied.value = false;
}

function ask(type, keyId) {
  pending.value = { type, keyId };
}

async function confirmPending() {
  if (!pending.value) {
    return;
  }
  const { type, keyId } = pending.value;
  busyKeyId.value = keyId;
  createError.value = '';
  try {
    if (type === 'rotate') {
      showSecret(await portalApi.rotateApiKey(keyId, newIdempotencyKey()));
    } else {
      await portalApi.revokeApiKey(keyId, newIdempotencyKey());
      if (revealedKeyId.value === keyId) {
        dismissSecret();
      }
    }
    await refresh({ silent: true });
  } catch (err) {
    createError.value = err?.message || t('apiKeys.createError');
  } finally {
    pending.value = null;
    busyKeyId.value = '';
  }
}
</script>

<template>
  <section class="em-page em-apikeys">
    <header class="em-apikeys__head">
      <p class="em-apikeys__subtitle">{{ t('apiKeys.subtitle') }}</p>
      <div class="em-apikeys__head-actions">
        <span v-if="keys.length" class="md-chip md-chip--neutral">
          {{ t('apiKeys.activeKeys', { count: activeCount }) }}
        </span>
        <button v-if="canWrite && !formOpen" type="button" class="md-btn md-btn-filled" @click="openForm">
          <span class="material-symbols-outlined" aria-hidden="true">add</span>
          {{ t('apiKeys.create') }}
        </button>
      </div>
    </header>

    <p class="fn-notice">
      <span class="material-symbols-outlined" aria-hidden="true">shield_lock</span>
      <span>{{ t('apiKeys.secretNote') }} {{ t('apiKeys.oneIntegration') }}</span>
    </p>

    <form v-if="formOpen" class="md-card em-apikeys-form" @submit.prevent="createKey">
      <header class="em-apikeys-section-head">
        <span class="em-apikeys-section-head__icon material-symbols-outlined" aria-hidden="true">key</span>
        <div>
          <h2>{{ t('apiKeys.formTitle') }}</h2>
          <p>{{ t('apiKeys.formSubtitle') }}</p>
        </div>
      </header>

      <div class="em-apikeys-form__grid">
        <label class="em-field em-field--wide">
          <span class="em-field__label">{{ t('apiKeys.name') }}</span>
          <input v-model="keyName" class="md-input" type="text" maxlength="80" required :placeholder="t('apiKeys.namePlaceholder')" />
        </label>

        <fieldset class="em-field em-field--wide">
          <legend class="em-field__label">{{ t('apiKeys.scopes') }}</legend>
          <div class="em-scope-grid">
            <label class="em-scope-option" :class="{ 'is-checked': allowRead }">
              <input v-model="allowRead" type="checkbox" />
              <span class="material-symbols-outlined" aria-hidden="true">visibility</span>
              <span>
                <strong>{{ t('apiKeys.scopeRead') }}</strong>
                <small>{{ t('apiKeys.scopeReadHint') }}</small>
              </span>
            </label>
            <label class="em-scope-option" :class="{ 'is-checked': allowWrite }">
              <input v-model="allowWrite" type="checkbox" />
              <span class="material-symbols-outlined" aria-hidden="true">send</span>
              <span>
                <strong>{{ t('apiKeys.scopeWrite') }}</strong>
                <small>{{ t('apiKeys.scopeWriteHint') }}</small>
              </span>
            </label>
          </div>
        </fieldset>

        <label class="em-field">
          <span class="em-field__label">{{ t('apiKeys.expires') }}</span>
          <input v-model="expiresDays" class="md-input" type="number" min="1" max="366" placeholder="90" />
          <small class="em-field__hint">{{ t('apiKeys.expiresHint') }}</small>
        </label>

        <label class="em-field">
          <span class="em-field__label">{{ t('apiKeys.cidrs') }}</span>
          <input v-model="cidrs" class="md-input" type="text" dir="ltr" placeholder="203.0.113.0/24" />
          <small class="em-field__hint">{{ t('apiKeys.cidrsHint') }}</small>
        </label>
      </div>

      <p v-if="createError" class="md-alert md-alert--error" role="alert">{{ createError }}</p>

      <footer class="em-apikeys-form__actions">
        <button type="button" class="md-btn md-btn-outlined" @click="closeForm">{{ t('apiKeys.cancel') }}</button>
        <button type="submit" class="md-btn md-btn-filled" :disabled="creating || !selectedScopes().length">
          <span class="material-symbols-outlined" aria-hidden="true">{{ creating ? 'progress_activity' : 'key' }}</span>
          {{ t('apiKeys.create') }}
        </button>
      </footer>
    </form>

    <article v-if="revealedSecret" class="md-card em-secret-card" role="status">
      <header class="em-apikeys-section-head">
        <span class="em-apikeys-section-head__icon material-symbols-outlined" aria-hidden="true">warning</span>
        <div>
          <h2>{{ t('apiKeys.secretTitle') }}</h2>
          <p>{{ t('apiKeys.secretOnce') }}</p>
        </div>
      </header>
      <div class="em-secret-card__value" dir="ltr">
        <code>{{ revealedSecret }}</code>
        <button type="button" class="md-btn md-btn-filled" @click="copySecret">
          <span class="material-symbols-outlined" aria-hidden="true">{{ copied ? 'check' : 'content_copy' }}</span>
          {{ copied ? t('apiKeys.copied') : t('apiKeys.copy') }}
        </button>
      </div>
      <p class="em-secret-card__hint">{{ t('apiKeys.headerHint') }}</p>
      <footer class="em-apikeys-form__actions">
        <button type="button" class="md-btn md-btn-outlined" @click="dismissSecret">{{ t('apiKeys.secretDone') }}</button>
      </footer>
    </article>

    <p v-if="!formOpen && (createError || error)" class="md-alert md-alert--error" role="alert">{{ createError || error }}</p>

    <div v-if="loading" class="em-apikeys-grid">
      <div v-for="index in 3" :key="index" class="md-card"><div class="md-skeleton" style="height: 8rem" /></div>
    </div>
    <EmptyState v-else-if="!keys.length" :title="t('apiKeys.emptyTitle')" icon="key" />
    <div v-else class="em-apikeys-grid">
      <article
        v-for="item in keys"
        :key="item.id"
        class="md-card em-apikey-card"
        :class="{ 'is-inactive': item.status !== 'active' }"
      >
        <header class="em-apikey-card__head">
          <div class="em-apikey-card__icon" aria-hidden="true">
            <span class="material-symbols-outlined">key</span>
          </div>
          <div class="em-apikey-card__name">
            <strong>{{ item.name || item.id }}</strong>
            <small dir="ltr">{{ item.id }}</small>
          </div>
          <StatusChip :status="item.status" />
        </header>

        <code class="em-apikey-card__secret" dir="ltr">{{ maskedKey(item) }}</code>

        <div v-if="item.scopes?.length" class="em-apikey-card__chips">
          <span v-for="scope in item.scopes" :key="scope" class="md-chip md-chip--warning">{{ scopeLabel(scope) }}</span>
        </div>

        <dl class="em-apikey-card__meta">
          <div>
            <dt>{{ t('apiKeys.createdAt') }}</dt>
            <dd>{{ formatDate(item.createdAt) || '—' }}</dd>
          </div>
          <div>
            <dt>{{ t('apiKeys.expiresAt') }}</dt>
            <dd>{{ formatDate(item.expiresAt) || t('apiKeys.never') }}</dd>
          </div>
          <div>
            <dt>{{ t('apiKeys.cidrs') }}</dt>
            <dd dir="ltr">{{ item.allowedCidrs?.length ? item.allowedCidrs.join(', ') : t('apiKeys.anyNetwork') }}</dd>
          </div>
        </dl>

        <footer v-if="canWrite && (item.rotatable || item.revocable)" class="em-apikey-card__actions">
          <template v-if="pending?.keyId === item.id">
            <span class="em-apikey-card__confirm">
              {{ pending.type === 'rotate' ? t('apiKeys.rotateConfirm') : t('apiKeys.revokeConfirm') }}
            </span>
            <button type="button" class="md-btn md-btn-outlined" @click="pending = null">{{ t('apiKeys.cancel') }}</button>
            <button
              type="button"
              class="md-btn"
              :class="pending.type === 'revoke' ? 'em-btn-danger' : 'md-btn-filled'"
              :disabled="busyKeyId === item.id"
              @click="confirmPending"
            >
              {{ pending.type === 'rotate' ? t('apiKeys.rotate') : t('apiKeys.revoke') }}
            </button>
          </template>
          <template v-else>
            <button v-if="item.rotatable" type="button" class="md-btn md-btn-outlined" @click="ask('rotate', item.id)">
              <span class="material-symbols-outlined" aria-hidden="true">autorenew</span>
              {{ t('apiKeys.rotate') }}
            </button>
            <button v-if="item.revocable" type="button" class="md-btn md-btn-outlined em-btn-danger-text" @click="ask('revoke', item.id)">
              <span class="material-symbols-outlined" aria-hidden="true">block</span>
              {{ t('apiKeys.revoke') }}
            </button>
          </template>
        </footer>
      </article>
    </div>

    <ApiKeyUsagePanel v-if="canRead" :keys="keys" />
    <ApiKeyUsageGuide :workspace-id="session.workspaceId" :secret="revealedSecret" />
  </section>
</template>
