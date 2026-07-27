import { t } from '../i18n';

export function SkipToContent() {
  return (
    <a className="skip-link" href="#main-content">
      {t('a11y.skip')}
    </a>
  );
}
