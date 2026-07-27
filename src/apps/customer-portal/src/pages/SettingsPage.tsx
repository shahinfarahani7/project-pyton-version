import { t } from '../i18n';

export function SettingsPage() {
  return (
    <section className="panel">
      <h1>{t('nav.settings')}</h1>
      <p>Content Security Policy blocks inline scripts. Telemetry is opt-out via environment configuration.</p>
    </section>
  );
}
