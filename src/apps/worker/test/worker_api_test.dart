import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/api/worker_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enrollment routes match worker API contract', () {
    expect(WorkerRoutes.createChallenge, '/auth/challenges');
    expect(WorkerRoutes.registerDevice, '/workers/register');
    expect(WorkerRoutes.refreshSession, '/sessions:refresh');
    expect(WorkerRoutes.workerHeartbeat('wrk_test'), '/workers/wrk_test/heartbeat');
    expect(WorkerRoutes.enrollmentRoutes.length, 4);
  });

  test('model delivery routes match worker API contract', () {
    expect(WorkerRoutes.modelManifest('mdv_test'), '/models/mdv_test/manifest');
    expect(WorkerRoutes.reportModelInstall('mdv_test'), '/models/mdv_test:report-install');
  });

  test('execution routes match worker API contract', () {
    expect(WorkerRoutes.nextAssignment, '/assignments:next');
    expect(WorkerRoutes.completeAssignment('asg_test'), '/assignments/asg_test:complete');
    expect(WorkerRoutes.executionRoutes.length, 7);
  });

  test('WorkerApiException preserves problem code', () {
    final error = WorkerApiException(409, 'CHALLENGE_EXPIRED', 'nonce expired');
    expect(error.toString(), contains('CHALLENGE_EXPIRED'));
  });
}
