import 'package:edgemint_worker/runtime/transport_recovery_journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransportRecoveryJournal', () {
    test('retransmits pending entries without replacing acknowledged ones', () async {
      final journal = TransportRecoveryJournal();
      final sentKeys = <String>[];
      journal.bindRetransmit((entry) async {
        sentKeys.add(entry.idempotencyKey);
      });
      journal.record(
        TransportJournalEntry(
          assignmentId: 'asg-1',
          eventKind: 'progress',
          idempotencyKey: 'progress-att-1-map-1000',
          path: '/assignments/asg-1:progress',
          bodyJson: '{"sequence":1}',
          recordedAt: DateTime.utc(2026, 9, 6),
        ),
      );
      journal.record(
        TransportJournalEntry(
          assignmentId: 'asg-1',
          eventKind: 'checkpoint',
          idempotencyKey: 'checkpoint-att-1-chunk-0',
          path: '/assignments/asg-1:checkpoint',
          bodyJson: '{"sequence":1}',
          recordedAt: DateTime.utc(2026, 9, 6),
          acknowledged: true,
        ),
      );

      final count = await journal.retransmitPending();

      expect(count, 1);
      expect(sentKeys, ['progress-att-1-map-1000']);
    });

    test('serialize and restore round-trip', () {
      final journal = TransportRecoveryJournal();
      journal.record(
        TransportJournalEntry(
          assignmentId: 'asg-2',
          eventKind: 'progress',
          idempotencyKey: 'progress-att-2-reduce-5000',
          path: '/assignments/asg-2:progress',
          bodyJson: '{"sequence":2}',
          recordedAt: DateTime.utc(2026, 9, 6),
        ),
      );
      final restored = TransportRecoveryJournal()..restore(journal.serialize());
      expect(restored.pendingEntries.length, 1);
      expect(restored.pendingEntries.first.idempotencyKey, 'progress-att-2-reduce-5000');
    });
  });
}
