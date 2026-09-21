/// Synthetic payloads for JSON extraction edge cases (not from a live run).
const syntheticLiteralNewlineInSummary =
    '```json\n{"summary":"Line one\nLine two","keyPoints":["a","b","c","d"],'
    '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}\n'
    '``';

const syntheticValidCurlyQuotesInSummary =
    '{"summary":"The screen showed “five minutes away” for an hour.",'
    '"keyPoints":["a"],"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
