/** Grocery regression fixture options — not sent by the portal UI; use explicit API/tests only. */
export const TEXT_SUMMARIZE_PORTAL_OPTIONS = {
  schemaVersion: '1',
  maxSummaryWords: 80,
  keyPointCount: 5,
  coverageAxes: ['delivery', 'tracking', 'product', 'billing', 'support'],
  billingRules: ['pending_not_confirmed_charge', 'promised_not_completed_refund'],
};
