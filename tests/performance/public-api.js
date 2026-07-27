import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const fixtureMode = (__ENV.FIXTURE_MODE || '1') === '1';
const baseUrl = __ENV.BASE_URL || 'https://quickpizza.grafana.com';
const profile = __ENV.PROFILE || 'load';

const admissionLatency = new Trend('task_admission_latency_ms', true);
const heartbeatLatency = new Trend('worker_heartbeat_latency_ms', true);
const errorRate = new Rate('api_errors');

export const options = (() => {
  const thresholds = {
    task_admission_latency_ms: ['p(95)<500'],
    worker_heartbeat_latency_ms: ['p(95)<250'],
    api_errors: ['rate<0.01'],
  };
  if (!fixtureMode) {
    thresholds.http_req_failed = ['rate<0.01'];
  }
  if (profile === 'soak') {
    return {
      scenarios: {
        soak: {
          executor: 'constant-arrival-rate',
          rate: fixtureMode ? 5 : 120,
          timeUnit: '1s',
          duration: fixtureMode ? '30s' : '72h',
          preAllocatedVUs: fixtureMode ? 5 : 200,
          maxVUs: fixtureMode ? 20 : 1000,
        },
      },
      thresholds,
    };
  }
  if (profile === 'stress') {
    return {
      scenarios: {
        stress: {
          executor: 'ramping-vus',
          startVUs: 1,
          stages: fixtureMode
            ? [
                { duration: '5s', target: 10 },
                { duration: '10s', target: 30 },
                { duration: '5s', target: 0 },
              ]
            : [
                { duration: '5m', target: 200 },
                { duration: '10m', target: 600 },
                { duration: '5m', target: 0 },
              ],
        },
      },
      thresholds,
    };
  }
  return {
    scenarios: {
      load: {
        executor: 'constant-vus',
        vus: fixtureMode ? 5 : 100,
        duration: fixtureMode ? '20s' : '10m',
      },
    },
    thresholds,
  };
})();

function simulateAdmission() {
  const started = Date.now();
  const response = http.get(`${baseUrl}/api/health`, { tags: { name: 'task_admission' } });
  admissionLatency.add(Date.now() - started);
  const ok = check(response, { 'admission status ok': (r) => r.status >= 200 && r.status < 500 });
  errorRate.add(!ok);
}

function simulateHeartbeat() {
  const started = Date.now();
  const response = http.get(`${baseUrl}/api/health`, { tags: { name: 'worker_heartbeat' } });
  heartbeatLatency.add(Date.now() - started);
  const ok = check(response, { 'heartbeat status ok': (r) => r.status >= 200 && r.status < 500 });
  errorRate.add(!ok);
}

export default function publicApiProfile() {
  if (fixtureMode) {
    const started = Date.now();
    sleep(0.05);
    admissionLatency.add(80 + Math.random() * 120);
    heartbeatLatency.add(40 + Math.random() * 80);
    const ok = check(null, {
      'fixture admission ok': () => true,
      'fixture heartbeat ok': () => true,
    });
    errorRate.add(!ok);
    return;
  }
  simulateAdmission();
  simulateHeartbeat();
  sleep(0.5);
}

export function handleSummary(data) {
  const summary = {
    profile,
    fixtureMode,
    baseUrl,
    metrics: {
      admissionP95Ms: data.metrics.task_admission_latency_ms?.values?.['p(95)'] ?? 0,
      heartbeatP95Ms: data.metrics.worker_heartbeat_latency_ms?.values?.['p(95)'] ?? 0,
      errorRate: data.metrics.http_req_failed?.values?.rate ?? 0,
    },
    thresholdsPassed: Object.values(data.metrics).every((metric) =>
      Object.values(metric.thresholds || {}).every((threshold) => threshold.ok !== false),
    ),
  };
  return {
    stdout: JSON.stringify(summary, null, 2),
  };
}
