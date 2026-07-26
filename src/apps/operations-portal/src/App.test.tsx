import { describe, expect, it } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import { App } from './App';
describe('operations-portal', () => { it('renders the branded shell', () => { const html=renderToStaticMarkup(<App />); expect(html).toContain('EdgeMint Operations Portal'); expect(html).toContain('workspace isolation'); }); });
