import '../contracts/worker_task_result.dart';

class IdempotencyStore {
  final Map<String, WorkerTaskResult> _cache = {};

  WorkerTaskResult? get(String key) => _cache[key];

  void put(String key, WorkerTaskResult result) {
    _cache[key] = result;
  }

  void clear() => _cache.clear();
}
