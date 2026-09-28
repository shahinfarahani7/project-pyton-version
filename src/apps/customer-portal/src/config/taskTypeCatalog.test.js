import { describe, expect, it } from 'vitest';

import { resolveTaskTypeForIntake } from '../config/taskTypeCatalog.js';

describe('resolveTaskTypeForIntake', () => {
  it('returns null when intake is empty', () => {
    expect(resolveTaskTypeForIntake({})).toBeNull();
    expect(resolveTaskTypeForIntake({ instructions: '   ' })).toBeNull();
  });

  it('maps text-only intake to text.direct', () => {
    expect(resolveTaskTypeForIntake({ instructions: 'Summarize in Persian' })).toBe('text.direct');
  });

  it('maps file intake to text.direct', () => {
    const file = new File(['x'], 'scan.png', { type: 'image/png' });
    expect(resolveTaskTypeForIntake({ file, instructions: '' })).toBe('text.direct');
  });
});
