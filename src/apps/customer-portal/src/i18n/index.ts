export type Locale = 'en' | 'fa';

const messages: Record<Locale, Record<string, string>> = {
  en: {
    'app.title': 'EdgeMint Customer Portal',
    'nav.dashboard': 'Dashboard',
    'nav.tasks': 'Tasks',
    'nav.files': 'Files',
    'nav.webhooks': 'Webhooks',
    'nav.apiKeys': 'API keys',
    'nav.billing': 'Billing',
    'nav.disputes': 'Disputes',
    'nav.team': 'Team',
    'nav.settings': 'Settings',
    'login.title': 'Sign in',
    'login.oidc': 'Continue with SSO',
    'login.dev': 'Development sign-in',
    'workspace.switch': 'Switch workspace',
    'error.boundary': 'Something went wrong',
    'error.sessionExpired': 'Your session expired. Sign in again.',
    'error.crossWorkspace': 'Cross-workspace access is blocked.',
    'a11y.skip': 'Skip to main content',
  },
  fa: {
    'app.title': 'پرتال مشتری EdgeMint',
    'nav.dashboard': 'داشبورد',
    'nav.tasks': 'وظایف',
    'nav.files': 'فایل‌ها',
    'nav.webhooks': 'Webhookها',
    'nav.apiKeys': 'کلیدهای API',
    'nav.billing': 'صورتحساب',
    'nav.disputes': 'اختلافات',
    'nav.team': 'تیم',
    'nav.settings': 'تنظیمات',
    'login.title': 'ورود',
    'login.oidc': 'ادامه با SSO',
    'login.dev': 'ورود توسعه',
    'workspace.switch': 'تغییر workspace',
    'error.boundary': 'خطایی رخ داد',
    'error.sessionExpired': 'نشست شما منقضی شده است.',
    'error.crossWorkspace': 'دسترسی بین workspace مسدود است.',
    'a11y.skip': 'رفتن به محتوای اصلی',
  },
};

export function resolveLocale(): Locale {
  const configured = import.meta.env.VITE_APP_LOCALE;
  return configured === 'fa' ? 'fa' : 'en';
}

export function t(key: string, locale: Locale = resolveLocale()): string {
  return messages[locale][key] ?? messages.en[key] ?? key;
}
