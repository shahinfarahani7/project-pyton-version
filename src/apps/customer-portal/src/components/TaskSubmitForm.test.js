import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

import TaskSubmitForm from './TaskSubmitForm.vue';

describe('TaskSubmitForm chat composer', () => {
  it('sends the typed message as a task from the chat composer', async () => {
    const wrapper = mount(TaskSubmitForm);

    expect(wrapper.text()).toContain('What should I do?');
    expect(wrapper.get('textarea').attributes('placeholder')).toBe('Message…');

    await wrapper.get('textarea').setValue('خلاصه این متن را بنویس');
    await wrapper.get('textarea').trigger('keydown', { key: 'Enter' });

    expect(wrapper.emitted('submit')[0][0]).toMatchObject({
      taskType: 'text.direct',
      instructions: 'خلاصه این متن را بنویس',
    });
  });

  it('shows the outgoing message while the task is submitting', async () => {
    const wrapper = mount(TaskSubmitForm);
    await wrapper.get('textarea').setValue('در حال ارسال');
    await wrapper.setProps({ submitting: true });

    expect(wrapper.text()).toContain('در حال ارسال');
    expect(wrapper.find('.em-chat__typing').exists()).toBe(true);
    expect(wrapper.get('.em-chat__send').attributes('disabled')).toBeDefined();
  });
});
