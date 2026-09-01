import { createApp } from 'vue';

import App from './App.vue';
import { vReveal } from './directives/reveal.js';
import router from './router';
import './styles.css';

createApp(App).use(router).directive('reveal', vReveal).mount('#root');
