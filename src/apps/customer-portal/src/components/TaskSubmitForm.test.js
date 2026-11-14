import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

import TaskSubmitForm from './TaskSubmitForm.vue';

describe('TaskSubmitForm chat composer', () => {
  it('sends the typed message as a task from the chat composer', async () => {
    const wrapper = mount(TaskSubmitForm);

    expect(wrapper.text()).toContain('What should I do?');
    expect(wrapper.get('textarea').attributes('placeholder')).toBe('Ask FibonAI to summarize, write or analyze…');

    await wrapper.get('textarea').setValue('خلاصه این متن را بنویس');
    await wrapper.get('textarea').trigger('keydown', { key: 'Enter' });

    expect(wrapper.emitted('submit')[0][0]).toMatchObject({
      taskType: 'text.direct',
      instructions: 'خلاصه این متن را بنویس',
    });
  });

  it('grows the composer to fit a long message', async () => {
    const wrapper = mount(TaskSubmitForm);
    const field = wrapper.get('textarea');
    Object.defineProperty(field.element, 'scrollHeight', { configurable: true, value: 180 });

    await field.setValue(`${'یک خط بلند از متن تسک. '.repeat(8)}\n`.repeat(6));

    expect(field.element.style.height).toBe('180px');
  });

  it('shows the outgoing message while the task is submitting', async () => {
    const wrapper = mount(TaskSubmitForm);
    await wrapper.get('textarea').setValue('در حال ارسال');
    await wrapper.setProps({ submitting: true });

    expect(wrapper.text()).toContain('در حال ارسال');
    expect(wrapper.find('.em-chat__typing').exists()).toBe(true);
    expect(wrapper.get('.em-chat__send').attributes('disabled')).toBeDefined();
  });

  it('accepts a file up to 50 MB and rejects a larger one', async () => {
    async function attach(wrapper, size) {
      const input = wrapper.get('input[type="file"]');
      const file = new File(['x'], 'schedule.png', { type: 'image/png' });
      Object.defineProperty(file, 'size', { configurable: true, value: size });
      Object.defineProperty(input.element, 'files', { configurable: true, value: [file] });
      await input.trigger('change');
    }

    const accepted = mount(TaskSubmitForm);
    await attach(accepted, 50 * 1024 * 1024);
    await accepted.get('form').trigger('submit');
    expect(accepted.emitted('submit')).toHaveLength(1);
    expect(accepted.emitted('submit')[0][0].inputFile.name).toBe('schedule.png');
    expect(accepted.text()).not.toContain('File is too large');

    const rejected = mount(TaskSubmitForm);
    await attach(rejected, 50 * 1024 * 1024 + 1);
    await rejected.get('form').trigger('submit');
    expect(rejected.emitted('submit')).toBeUndefined();
    expect(rejected.text()).toContain('File is too large (max 50 MB).');
  });
});
