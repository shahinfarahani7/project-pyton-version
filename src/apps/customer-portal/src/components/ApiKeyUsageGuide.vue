<script setup>
import { computed, ref } from 'vue';
import { t } from '../i18n';

const props = defineProps({
  workspaceId: { type: String, default: '' },
  secret: { type: String, default: '' },
});

const tab = ref('json');
const copiedId = ref('');

const apiUrl = computed(() => `${globalThis.location?.origin ?? ''}/v1/workspaces/${props.workspaceId}/tasks`);
const keyValue = computed(() => props.secret || 'emk_YOUR_SECRET');

const jsonBody = `{
  "taskType": "text.summarize",
  "inputText": "Text you want summarized...",
  "instructions": "Keep it short"
}`;

const snippets = computed(() => ({
  json: [
    { id: 'json-body', label: t('apiKeys.guideBody'), code: jsonBody },
    {
      id: 'json-curl',
      label: 'cURL',
      code: `curl -X POST "${apiUrl.value}" \\
  -H "X-EdgeMint-Key: ${keyValue.value}" \\
  -H "Content-Type: application/json" \\
  -d '${jsonBody.replaceAll('\n', '\n  ')}'`,
    },
  ],
  form: [
    {
      id: 'form-fields',
      label: t('apiKeys.guideBody'),
      code: `taskType      = document.ocr
inputFile     = @receipt.png
instructions  = Extract all text`,
    },
    {
      id: 'form-curl',
      label: 'cURL',
      code: `curl -X POST "${apiUrl.value}" \\
  -H "X-EdgeMint-Key: ${keyValue.value}" \\
  -F "taskType=document.ocr" \\
  -F "inputFile=@./receipt.png" \\
  -F "instructions=Extract all text"`,
    },
  ],
  list: [
    {
      id: 'list-curl',
      label: 'cURL',
      code: `curl "${apiUrl.value}" \\
  -H "X-EdgeMint-Key: ${keyValue.value}"`,
    },
  ],
}));

const tabs = computed(() => [
  { id: 'json', label: t('apiKeys.usageJson'), method: 'POST' },
  { id: 'form', label: t('apiKeys.usageForm'), method: 'POST' },
  { id: 'list', label: t('apiKeys.usageList'), method: 'GET' },
]);

const fields = [
  { name: 'taskType', type: 'string', required: true, hint: 'apiKeys.fieldTaskType' },
  { name: 'inputText', type: 'string', required: false, hint: 'apiKeys.fieldInputText' },
  { name: 'instructions', type: 'string', required: false, hint: 'apiKeys.fieldInstructions' },
  { name: 'inputFile', type: 'file', required: false, hint: 'apiKeys.fieldInputFile' },
  { name: 'summarizeOptions', type: 'object', required: false, hint: 'apiKeys.fieldSummarizeOptions' },
];

const responses = [
  { code: '201', tone: 'success', hint: 'apiKeys.resp201' },
  { code: '401', tone: 'error', hint: 'apiKeys.resp401' },
  { code: '403', tone: 'error', hint: 'apiKeys.resp403' },
  { code: '422', tone: 'warning', hint: 'apiKeys.resp422' },
];

async function copy(id, text) {
  try {
    await navigator.clipboard.writeText(text);
    copiedId.value = id;
    setTimeout(() => {
      if (copiedId.value === id) {
        copiedId.value = '';
      }
    }, 1600);
  } catch {
    copiedId.value = '';
  }
}
</script>

<template>
  <article class="md-card em-api-guide">
    <header class="em-apikeys-section-head">
      <span class="em-apikeys-section-head__icon material-symbols-outlined" aria-hidden="true">code</span>
      <div>
        <h2>{{ t('apiKeys.usageTitle') }}</h2>
        <p>{{ t('apiKeys.usageIntro') }}</p>
      </div>
    </header>

    <div class="em-api-guide__endpoint" dir="ltr">
      <span class="em-api-guide__label">{{ t('apiKeys.usageUrl') }}</span>
      <div class="em-api-guide__url">
        <code>{{ apiUrl }}</code>
        <button type="button" class="md-btn md-btn-outlined" @click="copy('url', apiUrl)">
          <span class="material-symbols-outlined" aria-hidden="true">{{ copiedId === 'url' ? 'check' : 'content_copy' }}</span>
        </button>
      </div>
      <div class="em-api-guide__header-row">
        <span class="em-api-guide__label">Header</span>
        <code>X-EdgeMint-Key: {{ keyValue }}</code>
      </div>
    </div>

    <div class="em-segmented" role="tablist">
      <button
        v-for="item in tabs"
        :key="item.id"
        type="button"
        role="tab"
        :aria-selected="tab === item.id"
        :class="{ 'is-active': tab === item.id }"
        @click="tab = item.id"
      >
        <span class="em-method" :class="`em-method--${item.method.toLowerCase()}`">{{ item.method }}</span>
        {{ item.label }}
      </button>
    </div>

    <div class="em-api-guide__snippets">
      <div v-for="snippet in snippets[tab]" :key="snippet.id" class="em-code-block" dir="ltr">
        <div class="em-code-block__bar">
          <span>{{ snippet.label }}</span>
          <button type="button" class="em-code-block__copy" @click="copy(snippet.id, snippet.code)">
            <span class="material-symbols-outlined" aria-hidden="true">{{ copiedId === snippet.id ? 'check' : 'content_copy' }}</span>
            {{ copiedId === snippet.id ? t('apiKeys.copied') : t('apiKeys.copySnippet') }}
          </button>
        </div>
        <pre><code>{{ snippet.code }}</code></pre>
      </div>
    </div>

    <div class="em-api-guide__ref">
      <section>
        <h3>{{ t('apiKeys.guideFields') }}</h3>
        <ul class="em-api-guide__list">
          <li v-for="field in fields" :key="field.name">
            <code dir="ltr">{{ field.name }}</code>
            <span class="em-api-guide__type">{{ field.type }}</span>
            <span v-if="field.required" class="md-chip md-chip--warning">{{ t('apiKeys.required') }}</span>
            <small>{{ t(field.hint) }}</small>
          </li>
        </ul>
      </section>
      <section>
        <h3>{{ t('apiKeys.guideResponses') }}</h3>
        <ul class="em-api-guide__list">
          <li v-for="item in responses" :key="item.code">
            <span class="md-chip" :class="`md-chip--${item.tone}`">{{ item.code }}</span>
            <small>{{ t(item.hint) }}</small>
          </li>
        </ul>
      </section>
    </div>
  </article>
</template>
