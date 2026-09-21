import 'package:edgemint_worker/inference/llm/map_partial_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapPartialValidator', () {
    test('accepts partial with key points and empty optional fields', () {
      final issues = MapPartialValidator.validate(
        partial: const {
          'summary': 'Late delivery on order A184.',
          'keyPoints': ['Order A184 arrived at 19:35.'],
          'mainComplaint': '',
          'suggestedImprovement': '',
          'missingOrUnclear': [],
        },
        generationTruncated: false,
      );
      expect(issues, isEmpty);
    });

    test('rejects truncated generation', () {
      final issues = MapPartialValidator.validate(
        partial: const {
          'summary': 'Partial summary',
          'keyPoints': ['fact'],
          'mainComplaint': '',
          'suggestedImprovement': '',
          'missingOrUnclear': [],
        },
        generationTruncated: true,
        stopReason: 'output_limit',
      );
      expect(issues, contains('map_partial_generation_truncated:output_limit'));
    });

    test('rejects summary-only labeled fallback shape', () {
      final issues = MapPartialValidator.validate(
        partial: const {
          'summary': 'Only a summary line was returned.',
          'keyPoints': [],
          'mainComplaint': '',
          'suggestedImprovement': '',
          'missingOrUnclear': [],
        },
        generationTruncated: false,
      );
      expect(issues, contains('map_partial_missing_key_points'));
    });
  });
}
