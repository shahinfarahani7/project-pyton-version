import 'package:edgemint_worker/validation/output_repetition_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [text] in [chunkSize] deltas to mimic streaming token delivery.
/// Reconstructed chunk boundaries may differ from native callbacks on device.
bool feedInChunks(OutputRepetitionGuard guard, String text, {int chunkSize = 4}) {
  var stopped = false;
  for (var index = 0; index < text.length; index += chunkSize) {
    final end = index + chunkSize > text.length ? text.length : index + chunkSize;
    stopped = guard.feed(text.substring(index, end)) || stopped;
    if (stopped) {
      break;
    }
  }
  return stopped;
}

void main() {
  test('stops a keyPoints array that loops one phrase', () {
    final guard = OutputRepetitionGuard();
    // The device reply repeated this item twelve times before the budget ran
    // out; the guard has to fire long before that.
    const item = '"the milk arrived on time",';
    var repeats = 0;
    var stopped = false;
    while (repeats < 12 && !stopped) {
      repeats += 1;
      stopped = guard.feed(item);
    }

    expect(stopped, isTrue);
    expect(repeats, lessThanOrEqualTo(5));
    expect(guard.lastTriggerMatchCount, greaterThanOrEqualTo(3));
  });

  test('leaves a varied reply alone', () {
    final guard = OutputRepetitionGuard();
    const reply =
        '{"summary":"Deliveries slipped on three recent orders.",'
        '"keyPoints":["Order A184 arrived at 19:35 instead of 19:00",'
        '"Tracking showed five minutes away for an hour",'
        '"Lactose-free milk was substituted although substitutions are off"],'
        '"mainComplaint":"An explicitly disabled substitution was delivered",'
        '"suggestedImprovement":"Block substitutions when the setting is off",'
        '"missingOrUnclear":["Whether the pending authorization will drop"]}';

    expect(feedInChunks(guard, reply), isFalse);
  });

  test('ignores a short reply that repeats a word', () {
    final guard = OutputRepetitionGuard();
    expect(guard.feed('yes yes yes'), isFalse);
  });

  test(
    'does not stop map JSON that reuses phrasing across fields '
    '(tsk_dev_01a0f237 replay; chunk boundaries are approximate)',
    () {
      const capturedReply = '''
json
{
  "summary": "Customer received incorrect milk in two consecutive deliveries, despite disabling substitutions. The first order arrived on time but had a late delivery estimate. The second order arrived on time but contained incorrect milk despite the substitution setting being disabled.",
  "keyPoints": ["Incorrect milk in two consecutive deliveries despite substitution setting disabled", "Late delivery estimate for first order", "Substitution setting disabled for second order"],
  "mainComplaint": "Incorrect milk in two consecutive''';

      final guard = OutputRepetitionGuard();
      expect(feedInChunks(guard, capturedReply), isFalse);
    },
  );

  test('global-only matcher would have stopped the captured map reply', () {
    const capturedReply = '''
json
{
  "summary": "Customer received incorrect milk in two consecutive deliveries, despite disabling substitutions. The first order arrived on time but had a late delivery estimate. The second order arrived on time but contained incorrect milk despite the substitution setting being disabled.",
  "keyPoints": ["Incorrect milk in two consecutive deliveries despite substitution setting disabled", "Late delivery estimate for first order", "Substitution setting disabled for second order"],
  "mainComplaint": "Incorrect milk in two consecutive''';

    final normalized = capturedReply.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const windowChars = 32;
    const minRepeats = 3;
    final window = normalized.substring(normalized.length - windowChars);
    var count = 0;
    var index = normalized.indexOf(window);
    while (index >= 0) {
      count += 1;
      index = normalized.indexOf(window, index + 1);
    }

    expect(count, greaterThanOrEqualTo(minRepeats));
  });

  test('records diagnostics when a genuine loop is detected', () {
    final guard = OutputRepetitionGuard();
    const loop = 'repeat this exact phrase now ';
    var stopped = false;
    while (!stopped) {
      stopped = guard.feed(loop);
    }

    expect(guard.lastTriggerWindow, isNotNull);
    expect(guard.lastTriggerMatchCount, greaterThanOrEqualTo(3));
    expect(guard.lastTriggerOutputLength, greaterThanOrEqualTo(96));
  });
}
