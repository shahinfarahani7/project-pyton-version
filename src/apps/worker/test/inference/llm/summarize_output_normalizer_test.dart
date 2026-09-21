import 'package:edgemint_worker/inference/llm/summarize_output_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves uncertainty items that share source vocabulary', () {
    const source =
        'One completed payment of \$64.80 and a pending authorization for \$64.80.';
    final result = SummarizeOutputNormalizer.normalize({
      'summary': 'Billing issue noted.',
      'keyPoints': ['Pending authorization for \$64.80 remains unresolved.'],
      'mainComplaint': 'Unauthorized substitution.',
      'suggestedImprovement': 'Audit approvals.',
      'missingOrUnclear': [
        'Whether the pending \$64.80 authorization becomes another charge.',
      ],
    });

    expect(
      result.normalized['missingOrUnclear'],
      [
        'Whether the pending \$64.80 authorization becomes another charge.',
      ],
    );
    expect(source, contains('\$64.80'));
  });

  test('preserves invalid field types for validation', () {
    final result = SummarizeOutputNormalizer.normalize({
      'summary': 'Summary text.',
      'keyPoints': [123, 'valid point'],
      'mainComplaint': 'Complaint.',
      'suggestedImprovement': 'Improve.',
      'missingOrUnclear': [],
    });

    expect(result.normalized['keyPoints'], [123, 'valid point']);
  });

  test('dedupes exact duplicates and drops empty strings only', () {
    final result = SummarizeOutputNormalizer.normalize({
      'summary': 'Summary.',
      'keyPoints': ['Same fact', 'same fact', '   ', 'Other fact'],
      'mainComplaint': 'Complaint.',
      'suggestedImprovement': 'Improve.',
      'missingOrUnclear': ['pending auth', 'pending auth'],
    });

    expect(result.normalized['keyPoints'], ['Same fact', 'Other fact']);
    expect(result.normalized['missingOrUnclear'], ['pending auth']);
  });
}
