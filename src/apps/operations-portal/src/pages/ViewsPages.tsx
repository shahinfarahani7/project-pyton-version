import { ResourceView } from '../components/ResourceView';

export function TasksPage() {
  return <ResourceView view="tasks" title="Tasks" />;
}

export function WorkersPage() {
  return <ResourceView view="workers" title="Workers" />;
}

export function ModelsPage() {
  return <ResourceView view="models" title="Models" />;
}

export function FraudPage() {
  return <ResourceView view="fraud" title="Fraud cases" />;
}

export function DisputesPage() {
  return <ResourceView view="disputes" title="Disputes" />;
}

export function ReconciliationPage() {
  return <ResourceView view="reconciliation" title="Reconciliation" />;
}

export function IncidentsPage() {
  return <ResourceView view="incidents" title="Incidents" />;
}
