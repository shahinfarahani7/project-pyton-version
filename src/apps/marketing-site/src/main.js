import { createApp } from 'vue';

import App from './App.vue';
import { vReveal } from './directives/reveal.js';
import router from './router';
import '@fontsource/cal-sans/400.css';
import '@fontsource/geist-sans/300.css';
import '@fontsource/geist-sans/400.css';
import '@fontsource/geist-sans/500.css';
import '@fontsource/geist-sans/600.css';
import '@fontsource/geist-mono/400.css';
import '@fontsource/geist-mono/500.css';
import './styles.css';

createApp(App).use(router).directive('reveal', vReveal).mount('#root');
