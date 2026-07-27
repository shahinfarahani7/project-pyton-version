import { Navigate, Route, Routes } from 'react-router-dom';

import { SessionProvider } from './auth/session';
import { AppShell } from './components/AppShell';
import { ProtectedRoute } from './components/ProtectedRoute';
import { ApprovalsPage } from './pages/ApprovalsPage';
import { DashboardPage } from './pages/DashboardPage';
import { EmergencyPage } from './pages/EmergencyPage';
import { LoginPage } from './pages/LoginPage';
import {
  DisputesPage,
  FraudPage,
  IncidentsPage,
  ModelsPage,
  ReconciliationPage,
  TasksPage,
  WorkersPage,
} from './pages/ViewsPages';

export function AppRoutes() {
  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route path="/login" element={<LoginPage />} />
        <Route element={<ProtectedRoute />}>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/tasks" element={<TasksPage />} />
          <Route path="/workers" element={<WorkersPage />} />
          <Route path="/models" element={<ModelsPage />} />
          <Route path="/fraud" element={<FraudPage />} />
          <Route path="/disputes" element={<DisputesPage />} />
          <Route path="/reconciliation" element={<ReconciliationPage />} />
          <Route path="/incidents" element={<IncidentsPage />} />
          <Route path="/approvals" element={<ApprovalsPage />} />
          <Route path="/emergency" element={<EmergencyPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}

export function App() {
  return (
    <SessionProvider>
      <AppRoutes />
    </SessionProvider>
  );
}
