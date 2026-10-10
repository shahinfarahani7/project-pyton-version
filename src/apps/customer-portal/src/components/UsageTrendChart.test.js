import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

import { session } from '../auth/session';
import DashboardPage from '../pages/DashboardPage.vue';
import UsageTrendChart from './UsageTrendChart.vue';

describe('UsageTrendChart', () => {
  it('switches the plotted range between day, week, and month', async () => {
    const wrapper = mount(UsageTrendChart, {
      props: {
        taskItems: [{ createdAt: new Date().toISOString() }],
      },
    });

    expect(wrapper.text()).toContain('Last 7 days');
    expect(wrapper.text()).not.toContain('Success Rate');
    expect(wrapper.findAll('circle.em-line-chart__dot')).toHaveLength(7);

    const dayButton = wrapper.findAll('button').find((button) => button.text() === 'Day');
    await dayButton.trigger('click');
    expect(wrapper.text()).toContain('Today');
    expect(wrapper.text()).toContain('Hourly avg');
    expect(wrapper.findAll('circle.em-line-chart__dot')).toHaveLength(24);

    const monthButton = wrapper.findAll('button').find((button) => button.text() === 'Month');
    await monthButton.trigger('click');
    expect(wrapper.text()).toContain('Last 30 days');
    expect(wrapper.findAll('circle.em-line-chart__dot')).toHaveLength(30);
  });

  it('replaces success and failure cards with usage rate', async () => {
    session.workspaceId = null;
    const wrapper = mount(DashboardPage, {
      global: { stubs: { RouterLink: true } },
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('Usage Rate');
    expect(wrapper.text()).not.toContain('Success Rate');
    expect(wrapper.text()).not.toContain('Failed / Rejected');
    expect(wrapper.text()).toContain('Day');
    expect(wrapper.text()).toContain('Week');
    expect(wrapper.text()).toContain('Month');
    expect(wrapper.findAll('rect.em-bar-chart__bar').length).toBeGreaterThan(0);
    expect(wrapper.find('path.em-line-chart__line').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Workspace ID');
    expect(wrapper.text()).not.toContain('Session ID');
  });
});
