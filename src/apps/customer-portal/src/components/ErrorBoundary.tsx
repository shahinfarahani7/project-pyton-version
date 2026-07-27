import { Component, type ErrorInfo, type ReactNode } from 'react';

import { t } from '../i18n';
import { trackEvent } from '../telemetry';

type Props = { children: ReactNode };
type State = { hasError: boolean };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    trackEvent('portal.error.boundary', { message: error.message, componentStack: info.componentStack ?? '' });
  }

  render() {
    if (this.state.hasError) {
      return (
        <section role="alert" className="panel error-panel">
          <h1>{t('error.boundary')}</h1>
          <p>{t('error.sessionExpired')}</p>
        </section>
      );
    }
    return this.props.children;
  }
}
