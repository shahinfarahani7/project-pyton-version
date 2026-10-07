import { describe, expect, it } from 'vitest';

import { taskListTitle, taskStatusGroup } from './format.js';

describe('taskListTitle', () => {
  it('uses the instruction line instead of the task id', () => {
    expect(
      taskListTitle({
        id: 'tsk_dev_ab12cd34',
        taskType: 'text.direct',
        instructions: 'درباره مورچه‌ها یک مقاله بنویس',
        inputPreview: 'ignored body',
      }),
    ).toBe('درباره مورچه‌ها یک مقاله بنویس');
  });

  it('falls back to the first input line', () => {
    expect(
      taskListTitle({
        id: 'tsk_dev_ab12cd34',
        taskType: 'text.direct',
        inputPreview: '## عنوان مقاله\nمتن بعدی',
      }),
    ).toBe('عنوان مقاله');
  });
});

describe('taskStatusGroup', () => {
  it('maps lifecycle values onto done, running, queued, and cancel', () => {
    expect(taskStatusGroup('succeeded')).toBe('done');
    expect(taskStatusGroup('completed')).toBe('done');
    expect(taskStatusGroup('in_progress')).toBe('running');
    expect(taskStatusGroup('pending')).toBe('queued');
    expect(taskStatusGroup('cancelled')).toBe('cancel');
  });
});
