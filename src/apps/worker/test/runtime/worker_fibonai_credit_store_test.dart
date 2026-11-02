import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_fibonai_credit_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credited assignments survive a new store on the same disk bytes', () async {
    final backing = InMemoryEncryptedStore();
    final first = WorkerFibonaiCreditStore(backing);
    await first.writeCreditedAssignmentIds({'asg_1', 'asg_2'});

    final reopened = WorkerFibonaiCreditStore(backing);
    final ids = await reopened.readCreditedAssignmentIds();
    expect(ids, {'asg_1', 'asg_2'});
  });

  test('empty or malformed credit records read as no credits', () async {
    final store = WorkerFibonaiCreditStore(InMemoryEncryptedStore());
    expect(await store.readCreditedAssignmentIds(), isEmpty);
  });
}
