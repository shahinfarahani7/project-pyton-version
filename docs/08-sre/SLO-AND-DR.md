# SLO and Disaster Recovery

| Capability | SLO |
|---|---:|
| Public API monthly availability | 99.95% |
| Worker Gateway monthly availability | 99.95% |
| Operations API monthly availability | 99.90% |
| Task admission p95 | ≤ 500 ms |
| Worker heartbeat p95 | ≤ 250 ms |
| Event publication p99 | ≤ 5 s |
| RPO | ≤ 5 minutes |
| RTO | ≤ 60 minutes |

Backups are encrypted, cross-region copied, immutable for the retention period, and restored monthly. A full regional failover exercise is required at least twice per year. A release cannot claim DR readiness until the latest exercise meets both RPO and RTO.
