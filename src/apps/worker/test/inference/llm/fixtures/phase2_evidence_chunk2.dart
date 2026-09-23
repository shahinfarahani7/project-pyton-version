/// Phase 2 evidence fixture (test-only; not production prompt text).
const phase2EvidenceChunk2 = {
  'schemaVersion': '2',
  'facts': [
    'Order B443: an extra authorization disappeared; one original charge remained completed.',
    'Order B426: refund received on business day 4 within five business days.',
    'Customer declined the coupon because it required a minimum purchase.',
    'Support claimed substitution was approved; customer denied approving it; no supporting record was provided.',
  ],
  'openItems': [
    'Order B426: how substitution occurred with substitutions disabled.',
    'Order B426: what evidence supports the approval claim.',
  ],
  'priority': 'unauthorized substitution and unsupported approval claim',
};

/// Valid partial with empty facts but non-empty openItems (must not be treated as empty).
const phase2EvidenceOpenItemsOnly = {
  'schemaVersion': '2',
  'facts': [],
  'openItems': ['Pending investigation into substitution approval.'],
  'priority': '',
};

/// Valid partial with empty facts/openItems but non-blank priority.
const phase2EvidencePriorityOnly = {
  'schemaVersion': '2',
  'facts': [],
  'openItems': [],
  'priority': 'customer prioritizes unauthorized substitution',
};

/// Structurally valid all-empty partial for a chunk with no task-relevant content.
const phase2EvidenceAllEmpty = {
  'schemaVersion': '2',
  'facts': [],
  'openItems': [],
  'priority': '',
};
