import { createApp } from 'vue';

import App from './App.vue';
import router from './router';
import { resolveLocale } from './i18n';
import './styles.css';

const locale = resolveLocale();
document.documentElement.lang = locale === 'fa' ? 'fa' : 'en';

createApp(App).use(router).mount('#root');
