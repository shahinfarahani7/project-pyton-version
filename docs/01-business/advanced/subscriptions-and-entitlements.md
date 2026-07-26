# Subscriptions and Entitlements

A plan name does not directly authorize a feature. The subscription resolves to a versioned EntitlementPolicy containing limits and feature flags.

- subscription period and invoice period are explicit.
- allowance consumption uses UsageEvent occurrence time, not processing time.
- overage uses the PriceBook version pinned to the subscription period unless the contract states otherwise.
- upgrades can be immediate and prorated; downgrades apply next period by default.
- concurrency is enforced at accepted lease count.
- retention and compliance entitlements cannot weaken mandatory DataPolicy limits.
