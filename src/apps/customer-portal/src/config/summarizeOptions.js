/** Default portal/API fixture (80w / 5kp) — never attached unless explicitly requested. */
export const TEXT_SUMMARIZE_PORTAL_OPTIONS = {
  schemaVersion: '1',
  maxSummaryWords: 80,
  keyPointCount: 5,
  coverageAxes: ['delivery', 'tracking', 'product', 'billing', 'support'],
  billingRules: ['pending_not_confirmed_charge', 'promised_not_completed_refund'],
};

/** Phase 1 grocery-feedback regression (100w / 4kp). Opt-in via task form checkbox only. */
export const PHASE1_TEXT_SUMMARIZE_REGRESSION_OPTIONS = {
  schemaVersion: '1',
  maxSummaryWords: 100,
  keyPointCount: 4,
  coverageAxes: ['delivery', 'substitution', 'payment_refund', 'coupon'],
  billingRules: ['pending_not_confirmed_charge', 'promised_not_completed_refund'],
};
