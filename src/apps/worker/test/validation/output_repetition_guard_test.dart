import 'package:edgemint_worker/validation/output_repetition_guard.dart';
import 'package:flutter_test/flutter_test.dart';

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

    var stopped = false;
    for (var index = 0; index < reply.length; index += 4) {
      final end = index + 4 > reply.length ? reply.length : index + 4;
      stopped = guard.feed(reply.substring(index, end)) || stopped;
    }

    expect(stopped, isFalse);
  });

  test('ignores a short reply that repeats a word', () {
    final guard = OutputRepetitionGuard();
    expect(guard.feed('yes yes yes'), isFalse);
  });
}
