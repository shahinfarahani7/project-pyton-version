import 'package:edgemint_worker/runtime/memory_accounting.dart';
import 'package:test/test.dart';

void main() {
  test('shared resident identity is counted once', () {
    final commitments = [
      MemoryAccounting.baseRuntimeCommitment(),
      MemoryAccounting.residentCommitment('mdv_qwen'),
      MemoryAccounting.residentCommitment('mdv_qwen'),
      MemoryAccounting.taskPeakCommitment(
        assignmentId: 'asg_1',
        taskType: 'text.summarize',
      ),
    ];
    final deduped = MemoryAccounting.dedupeResidents(commitments);
    expect(deduped.where((item) => item.kind == MemoryCommitmentKind.resident).length, 1);
  });

  test('warm resident remains after task peak removed from snapshot', () {
    final resident = MemoryAccounting.residentCommitment('mdv_qwen', memoryBytes: 700000000);
    final withTask = [
      MemoryAccounting.baseRuntimeCommitment(),
      resident,
      MemoryAccounting.taskPeakCommitment(assignmentId: 'asg_done', taskType: 'text.summarize'),
    ];
    final afterTask = [MemoryAccounting.baseRuntimeCommitment(), resident];
    expect(MemoryAccounting.accountedBytes(withTask), greaterThan(MemoryAccounting.accountedBytes(afterTask)));
    expect(
      MemoryAccounting.accountedBytes(afterTask),
      MemoryAccounting.fixedRuntimeBaseBytes + 700000000,
    );
  });
}
