# Capacity and performance runbook

## Forecast peak and headroom

- Forecast peak public API throughput: 1200 RPS
- Approved headroom: 15% (`HEADROOM_BPS=1500`)
- Effective planning target: 1380 RPS

## SLO gates

| Signal | Threshold |
|---|---:|
| Task admission p95 | ≤ 500 ms |
| Worker heartbeat p95 | ≤ 250 ms |
| Event publication p99 | ≤ 5 s |

## Profiles

1. **Load** — `k6 run tests/performance/public-api.js`
2. **Soak (72h)** — `PROFILE=soak k6 run tests/performance/public-api.js`
3. **Stress** — `PROFILE=stress k6 run tests/performance/public-api.js`
4. **Worker fleet** — `python tests/performance/worker_fleet_simulator.py`

## Backpressure and hot keys

- WebSocket/event relay in-flight cap: 256 messages
- Router queue uses deficit round-robin with starvation guard at 300 seconds
- Hot-key tests must show detection without unbounded queue growth

## Unit economics

- Stressed contribution margin must remain ≥ 15% (`1500 bps`)
- Admission fails closed when margin guard rejects a quote

## Evidence

Store results under `evidence/actual/capacity/` and validate with:

```bash
python tools/evaluate_capacity_evidence.py evidence/actual
```
