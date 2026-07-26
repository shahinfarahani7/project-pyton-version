# Canary and Rollback

Traffic stages are internal, 1%, 5%, 25%, and 100%. Each stage observes latency, error rate, saturation, security alerts, event lag, database locks, reconciliation drift, worker success rate, and margin for a minimum configured window. Any threshold breach automatically rolls back the image, freezes migrations that are not backward compatible, and opens an incident. Database changes must follow expand/migrate/contract and remain compatible with the previous application version during the canary.
