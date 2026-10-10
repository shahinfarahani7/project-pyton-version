import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { portalApi } from '../api/client';
import { session } from '../auth/session';
import TaskChatPage from './TaskChatPage.vue';

describe('TaskChatPage', () => {
  afterEach(() => {
    session.workspaceId = null;
    session.permissions = [];
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('opens a chat thread and shows the task answer above the composer', async () => {
    session.workspaceId = 'ws-chat';
    session.permissions = ['customer.tasks:read', 'customer.tasks:write'];
    vi.stubGlobal(
      'EventSource',
      class {
        addEventListener() {}
        close() {}
      },
    );
    vi.spyOn(portalApi, 'tasks').mockResolvedValue({ items: [] });
    vi.spyOn(portalApi, 'createTask').mockResolvedValue({
      id: 'tsk_chat',
      lifecycleStatus: 'queued',
      instructions: 'سلام',
    });
    vi.spyOn(portalApi, 'task').mockResolvedValue({
      id: 'tsk_chat',
      lifecycleStatus: 'succeeded',
      modelTranscript: 'این جواب تسک است',
    });

    const wrapper = mount(TaskChatPage, {
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('What should I do?');
    await wrapper.get('textarea').setValue('سلام');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('.em-chat-title').exists()).toBe(false);
    expect(wrapper.get('.em-chat__bubble--user').text()).toContain('سلام');
    expect(wrapper.text()).toContain('این جواب تسک است');
    expect(wrapper.get('.em-chat__bubble--assistant').text()).toContain('این جواب تسک است');
    wrapper.unmount();
  });

  it('shows existing tasks as the chat history', async () => {
    session.workspaceId = 'ws-chat';
    session.permissions = ['customer.tasks:read', 'customer.tasks:write'];
    vi.stubGlobal(
      'EventSource',
      class {
        addEventListener() {}
        close() {}
      },
    );
    vi.spyOn(portalApi, 'tasks').mockResolvedValue({
      items: [
        {
          id: 'tsk_old',
          createdAt: '2026-10-01T10:00:00Z',
          lifecycleStatus: 'succeeded',
          instructions: 'درباره مورچه‌ها بنویس',
          modelTranscript: 'مورچه‌ها گروهی زندگی می‌کنند.',
        },
      ],
    });

    const wrapper = mount(TaskChatPage, {
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();

    expect(wrapper.get('.em-chat-list').text()).toContain('درباره مورچه‌ها بنویس');
    expect(wrapper.find('.em-chat__bubble--assistant').exists()).toBe(false);

    await wrapper.get('.em-chat-list button').trigger('click');

    expect(wrapper.text()).toContain('مورچه‌ها گروهی زندگی می‌کنند.');
    expect(wrapper.text()).not.toContain('tsk_old');
    wrapper.unmount();
  });

  it('copies a text answer and downloads a result file', async () => {
    session.workspaceId = 'ws-chat';
    session.permissions = ['customer.tasks:read', 'customer.tasks:write'];
    vi.stubGlobal(
      'EventSource',
      class {
        addEventListener() {}
        close() {}
      },
    );
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });
    vi.spyOn(portalApi, 'tasks').mockResolvedValue({
      items: [
        {
          id: 'tsk_file',
          createdAt: '2026-10-02T10:00:00Z',
          lifecycleStatus: 'succeeded',
          instructions: 'عکس را جدا کن',
          modelTranscript: 'پس‌زمینه حذف شد',
          resultArtifactUrl: '/v1/workspaces/ws/tasks/tsk_file/result-file',
          inputLabel: 'photo.png',
        },
      ],
    });

    const wrapper = mount(TaskChatPage, {
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();
    await wrapper.get('.em-chat-list button').trigger('click');

    expect(wrapper.get('.em-chat__result-image').attributes('src')).toContain('result-file');
    expect(wrapper.get('.em-chat__download').attributes('download')).toBe('result-photo.png');
    const copyButtons = wrapper.findAll('.em-chat__copy');
    expect(copyButtons[0].classes()).toContain('em-chat__copy--top');
    await copyButtons[0].trigger('click');
    expect(writeText).toHaveBeenCalledWith('پس‌زمینه حذف شد');
    wrapper.unmount();
  });
});
