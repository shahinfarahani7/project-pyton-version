import catalogDocument from '../../../../shared/task-types/catalog.json';

/** @typedef {'text' | 'image' | 'document' | 'flex'} TaskInputMode */

/**
 * @typedef {Object} TaskTypeEntry
 * @property {string} value
 * @property {string} labelEn
 * @property {string} labelFa
 * @property {TaskInputMode} inputMode
 */

/**
 * @typedef {Object} TaskTypeCategory
 * @property {string} id
 * @property {string} labelEn
 * @property {string} labelFa
 * @property {TaskTypeEntry[]} types
 */

/** @type {TaskTypeCategory[]} */
export const taskTypeCategories = catalogDocument.categories;

const taskTypeIndex = new Map(
  taskTypeCategories.flatMap((category) =>
    category.types.map((entry) => [
      entry.value,
      {
        ...entry,
        categoryId: category.id,
        categoryLabelEn: category.labelEn,
        categoryLabelFa: category.labelFa,
      },
    ]),
  ),
);

/** @param {string} locale @returns {'en' | 'fa'} */
function normalizeLocale(locale) {
  return locale === 'fa' ? 'fa' : 'en';
}

/** @param {string} value @returns {TaskTypeEntry | undefined} */
export function getTaskType(value) {
  return taskTypeIndex.get(value);
}

/** @param {TaskTypeEntry} entry @param {string} locale */
export function taskTypeLabel(entry, locale) {
  const lang = normalizeLocale(locale);
  return lang === 'fa' ? entry.labelFa : entry.labelEn;
}

/** @param {TaskTypeCategory} category @param {string} locale */
export function categoryLabel(category, locale) {
  const lang = normalizeLocale(locale);
  return lang === 'fa' ? category.labelFa : category.labelEn;
}

/** @param {string} value */
export function taskTypeAccept(value) {
  const entry = getTaskType(value);
  if (!entry) {
    return '*/*';
  }
  switch (entry.inputMode) {
    case 'image':
      return 'image/*';
    case 'document':
      return '.txt,.md,.pdf,image/*';
    case 'text':
      return '.txt,.md,.csv,.json';
    default:
      return '.txt,.md,.pdf,image/*,.csv,.json';
  }
}

/** @param {string} value */
export function taskTypeNeedsText(value) {
  const entry = getTaskType(value);
  return entry?.inputMode === 'text';
}

/** @param {string} value */
export function taskTypeNeedsImage(value) {
  const entry = getTaskType(value);
  return entry?.inputMode === 'image';
}

/** @param {string} value */
export function taskTypeNeedsFlexJson(value) {
  const entry = getTaskType(value);
  return entry?.inputMode === 'flex';
}

/** @param {string} value @param {string} locale */
export function formatTaskType(value, locale) {
  const entry = getTaskType(value);
  if (!entry) {
    return value;
  }
  return taskTypeLabel(entry, locale);
}

/**
 * @param {string} query
 * @param {string} locale
 * @returns {TaskTypeCategory[]}
 */
export function filterTaskTypeCategories(query, locale) {
  const normalized = query.trim().toLocaleLowerCase();
  if (!normalized) {
    return taskTypeCategories;
  }

  return taskTypeCategories
    .map((category) => {
      const categoryHaystack = `${category.id} ${category.labelEn} ${category.labelFa}`.toLocaleLowerCase();
      const types = category.types.filter((entry) => {
        const haystack = `${entry.value} ${entry.labelEn} ${entry.labelFa} ${categoryHaystack}`;
        return haystack.toLocaleLowerCase().includes(normalized);
      });
      return types.length ? { ...category, types } : null;
    })
    .filter(Boolean);
}

/** @param {Error & { problem?: { detail?: string; title?: string; code?: string } }} error */
export function mapTaskInputError(error) {
  const problem = error?.problem ?? {};
  const detailValue = problem.detail;
  const detail =
    typeof detailValue === 'string'
      ? detailValue
      : typeof detailValue === 'object' && detailValue !== null && 'code' in detailValue
        ? String(detailValue.code)
        : String(problem.code ?? error?.message ?? problem.title ?? '');
  if (detail.includes('UNSUPPORTED_TASK_TYPE')) {
    return 'tasks.unsupportedTaskType';
  }
  if (detail.includes('INPUT_TEXT_REQUIRED')) {
    return 'tasks.inputTextRequired';
  }
  if (detail.includes('INPUT_IMAGE_REQUIRED')) {
    return 'tasks.inputImageRequired';
  }
  if (detail.includes('INPUT_FILE_OR_TEXT_REQUIRED')) {
    return 'tasks.inputFileOrTextRequired';
  }
  if (detail.includes('FLEX_INPUT_MUST_BE_JSON_OBJECT')) {
    return 'tasks.flexJsonRequired';
  }
  if (detail.includes('INPUT_FILE_TOO_LARGE')) {
    return 'tasks.inputFileTooLarge';
  }
  if (detail.includes('AUTH_INVALID_CREDENTIAL') || detail.includes('AUTH_SESSION_REVOKED')) {
    return 'tasks.sessionExpired';
  }
  return null;
}
