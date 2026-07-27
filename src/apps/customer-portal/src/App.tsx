import { Navigate, Route, Routes } from 'react-router-dom';

import { SessionProvider } from './auth/session';
import { AppShell } from './components/AppShell';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ProtectedRoute } from './components/ProtectedRoute';
import { ApiKeysPage } from './pages/ApiKeysPage';
import { BillingPage } from './pages/BillingPage';
import { DashboardPage } from './pages/DashboardPage';
import { DisputesPage } from './pages/DisputesPage';
import { FilesPage } from './pages/FilesPage';
import { LoginPage } from './pages/LoginPage';
import { SettingsPage } from './pages/SettingsPage';
import { TasksPage } from './pages/TasksPage';
import { TeamPage } from './pages/TeamPage';
import { WebhooksPage } from './pages/WebhooksPage';

export function AppRoutes() {
  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route path="/login" element={<LoginPage />} />
        <Route element={<ProtectedRoute />}>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/tasks" element={<TasksPage />} />
          <Route path="/files" element={<FilesPage />} />
          <Route path="/webhooks" element={<WebhooksPage />} />
          <Route path="/api-keys" element={<ApiKeysPage />} />
          <Route path="/billing" element={<BillingPage />} />
          <Route path="/disputes" element={<DisputesPage />} />
          <Route path="/team" element={<TeamPage />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}

export function App() {
  return (
    <ErrorBoundary>
      <SessionProvider>
        <AppRoutes />
      </SessionProvider>
    </ErrorBoundary>
  );
}
