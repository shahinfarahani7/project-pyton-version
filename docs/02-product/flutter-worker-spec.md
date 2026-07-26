# Flutter Worker Application Specification

## Tabs
Mine/Home, Missions, Models, Earnings, Minty, Device and Settings.

## Non-negotiable worker controls
- explicit availability toggle.
- Wi-Fi/cellular, charging, battery, thermal and schedule policies.
- visible foreground processing indicator where required by the platform.
- pause stops new offers; an active lease follows cancellation policy.
- exact model storage and estimated memory before download.
- no large payload retained in Dart heap; native runtime and file streaming are required.

## Minty behavior
- idle animation reflects verified availability, not hidden compute.
- task animation is driven by real state and progress.
- estimated reward is separated from verified and claimable balances.
- failures communicate reason, retry ownership and whether reward was affected.

## Memory budgets
- T1: native inference allocation <= 45% of currently available RAM, one model resident.
- T2/T3: <= 55%; vision preprocessing is tiled/streamed.
- T4/dedicated: policy-defined but thermal and OS limits still apply.
- low-memory signal checkpoints if safe, unloads the model and reports `RESOURCE_MEMORY_PRESSURE`.
