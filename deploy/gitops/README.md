# GitOps promotion

Production promotion uses digest-pinned Helm values overlays and progressive canary stages defined in `promotion/canary-stages.yaml`.

- Staging syncs from `environments/staging/values-overlay.yaml`
- Production promotion requires signed release evidence and an independent approver
- Automatic rollback reverts to `rollback/previous-release.json` when canary SLO gates fail
