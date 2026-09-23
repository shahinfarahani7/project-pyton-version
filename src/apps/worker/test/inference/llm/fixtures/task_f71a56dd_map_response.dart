/// Map-stage model output for task `tsk_dev_f71a56dd` (log 20260922-082720).
///
/// Extracted from [INFERENCE RESPONSE map] PART 1/2 + PART 2/2. Log prefixes
/// removed. The payload uses literal `\n` and `\"` characters (zero real
/// newlines) — model output, not Flutter log escaping.
///
/// Log metadata: chars=1362, utf8Bytes=1362,
/// sha256=5cbc6bca1457e7737b52a3b69a3a94fe4e4e74fbe3e73685f3abb3a46cca39ff, stopReason=model_eos, truncated=false.
const taskF71a56ddLogChars = 1362;
const taskF71a56ddLogUtf8Bytes = 1362;
const taskF71a56ddLogSha256 =
    '5cbc6bca1457e7737b52a3b69a3a94fe4e4e74fbe3e73685f3abb3a46cca39ff';

const taskF71a56ddMapResponseRaw =
    '```json\\n{\\n  \\"summary\\": \\"Customer received incorrect milk in a delivery with a disabled substitution setting, despite not approving it. The customer received two payments for t'
    'he same amount, one completed and one pending authorization, which the support team did not clarify. The customer requested a refund for the milk and a coupon for the incorrect ord'
    'er, but the refund was not processed yet and the coupon offer was not kept open. The customer wants to know how the incorrect milk reached the order with the substitution disabled '
    'and what evidence supports the approval claim.\\",\\n  \\"keyPoints\\": [\\n    \\"Incorrect milk in order B426 despite substitution setting disabled\\",\\n    \\"Two payments for the same '
    'amount in order B443\\",\\n    \\"Pending authorization for payment in order B443\\",\\n    \\"Customer requests refund and coupon for incorrect milk\\",\\n    \\"Pending refund and coupon '
    'offer not processed yet\\"\\n  ],\\n  \\"mainComplaint\\": \\"Incorrect milk in a delivery with a disabled substitution setting\\",\\n  \\"suggestedImprovement\\": \\"Clarify the pending auth'
    'orization for payment in order B443 and provide evidence for the approval claim regarding the incorrect milk in order B426\\",\\n  \\"missingOrUnclear\\": [\\n    \\"Pending refund and c'
    'oupon offer not processed yet\\",\\n    \\"Pending authorization for payment in order B443\\"\\n  ]\\n}\\n```'
;

/// Parsed object shape from the live run. Map stage does not cap keyPoints;
/// final keyPointCount is enforced only after reduce.
const taskF71a56ddExpectedKeyPointCount = 5;
