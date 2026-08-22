<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';

import {
  categoryLabel,
  filterTaskTypeCategories,
  getTaskType,
  taskTypeLabel,
} from '../config/taskTypeCatalog';
import { resolveLocale, t } from '../i18n';

const props = defineProps({
  modelValue: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const rootEl = ref(null);
const searchInputEl = ref(null);
const open = ref(false);
const searchQuery = ref('');
const activeIndex = ref(-1);

const locale = computed(() => resolveLocale());

const selectedEntry = computed(() => getTaskType(props.modelValue));

const displayValue = computed(() => {
  if (open.value) {
    return searchQuery.value;
  }
  if (selectedEntry.value) {
    return taskTypeLabel(selectedEntry.value, locale.value);
  }
  return searchQuery.value;
});

const filteredCategories = computed(() => filterTaskTypeCategories(searchQuery.value, locale.value));

const flatOptions = computed(() =>
  filteredCategories.value.flatMap((category) =>
    category.types.map((entry) => ({
      entry,
      category,
      key: entry.value,
    })),
  ),
);

watch(
  () => props.modelValue,
  () => {
    if (!open.value) {
      searchQuery.value = '';
    }
  },
);

watch(open, (isOpen) => {
  if (!isOpen) {
    searchQuery.value = '';
    activeIndex.value = -1;
  }
});

watch(flatOptions, () => {
  if (activeIndex.value >= flatOptions.value.length) {
    activeIndex.value = flatOptions.value.length - 1;
  }
});

function onDocumentPointerDown(event) {
  if (!rootEl.value?.contains(event.target)) {
    closeList();
  }
}

function openList() {
  if (props.disabled) {
    return;
  }
  open.value = true;
  searchQuery.value = '';
  activeIndex.value = -1;
  document.addEventListener('pointerdown', onDocumentPointerDown);
  nextTick(() => searchInputEl.value?.focus());
}

function closeList() {
  open.value = false;
  document.removeEventListener('pointerdown', onDocumentPointerDown);
}

function selectOption(value) {
  emit('update:modelValue', value);
  closeList();
}

function onInputClick() {
  if (props.disabled || open.value) {
    return;
  }
  openList();
}

function onInputInput(event) {
  searchQuery.value = event.target.value;
  open.value = true;
  activeIndex.value = flatOptions.value.length ? 0 : -1;
}

function onInputKeydown(event) {
  if (event.key === 'ArrowDown') {
    event.preventDefault();
    if (!open.value) {
      openList();
      return;
    }
    if (!flatOptions.value.length) {
      return;
    }
    activeIndex.value = (activeIndex.value + 1) % flatOptions.value.length;
    return;
  }
  if (event.key === 'ArrowUp') {
    event.preventDefault();
    if (!flatOptions.value.length) {
      return;
    }
    activeIndex.value = activeIndex.value <= 0 ? flatOptions.value.length - 1 : activeIndex.value - 1;
    return;
  }
  if (event.key === 'Enter') {
    if (open.value && activeIndex.value >= 0 && flatOptions.value[activeIndex.value]) {
      event.preventDefault();
      selectOption(flatOptions.value[activeIndex.value].entry.value);
    }
    return;
  }
  if (event.key === 'Escape') {
    event.preventDefault();
    closeList();
  }
}

onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', onDocumentPointerDown);
});
</script>

<template>
  <div ref="rootEl" class="task-type-picker">
    <div class="task-type-picker__control">
      <span class="material-symbols-outlined task-type-picker__icon" aria-hidden="true">search</span>
      <input
        ref="searchInputEl"
        class="md-input task-type-picker__input"
        type="search"
        role="combobox"
        aria-autocomplete="list"
        :aria-expanded="open"
        :aria-controls="'task-type-picker-list'"
        :placeholder="t('tasks.typeSearchPlaceholder')"
        :value="displayValue"
        :disabled="disabled"
        autocomplete="off"
        @click="onInputClick"
        @input="onInputInput"
        @keydown="onInputKeydown"
      />
      <button
        type="button"
        class="md-btn md-btn-text md-btn-compact task-type-picker__toggle"
        :disabled="disabled"
        :aria-label="t('tasks.typeSearchToggle')"
        @click="open ? closeList() : openList()"
      >
        <span class="material-symbols-outlined" aria-hidden="true">
          {{ open ? 'expand_less' : 'expand_more' }}
        </span>
      </button>
    </div>

    <div v-if="selectedEntry && !open" class="task-type-picker__meta md-hint">
      <code>{{ selectedEntry.value }}</code>
      ·
      {{
        locale === 'fa' ? selectedEntry.categoryLabelFa : selectedEntry.categoryLabelEn
      }}
    </div>

    <ul
      v-if="open"
      id="task-type-picker-list"
      class="task-type-picker__list"
      role="listbox"
    >
      <template v-if="flatOptions.length">
        <template v-for="category in filteredCategories" :key="category.id">
          <li class="task-type-picker__group" role="presentation">
            {{ categoryLabel(category, locale) }}
          </li>
          <li
            v-for="option in category.types"
            :key="option.value"
            role="option"
            class="task-type-picker__option"
            :class="{
              'task-type-picker__option--active':
                flatOptions[activeIndex]?.entry.value === option.value,
              'task-type-picker__option--selected': modelValue === option.value,
            }"
            :aria-selected="modelValue === option.value"
            @mousedown.prevent="selectOption(option.value)"
            @mouseenter="activeIndex = flatOptions.findIndex((item) => item.entry.value === option.value)"
          >
            <span class="task-type-picker__option-label">{{ taskTypeLabel(option, locale) }}</span>
            <span class="task-type-picker__option-code">{{ option.value }}</span>
          </li>
        </template>
      </template>
      <li v-else class="task-type-picker__empty" role="presentation">
        {{ t('tasks.typeSearchEmpty') }}
      </li>
    </ul>
  </div>
</template>
