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
    expect(
      WorkerRoutes.executionRoutes,
      [
        WorkerRoutes.nextAssignment,
        WorkerRoutes.assignmentInboxBootstrap,
        WorkerRoutes.renewAssignment('asg_example'),
        WorkerRoutes.reportAssignmentStarted('asg_example'),
        WorkerRoutes.progressAssignment('asg_example'),
        WorkerRoutes.checkpointAssignment('asg_example'),
        WorkerRoutes.completeAssignment('asg_example'),
        WorkerRoutes.failAssignment('asg_example'),
        WorkerRoutes.confirmPhysicalStop('asg_example'),
        WorkerRoutes.abandonAssignment('asg_example'),
      ],
    );
    expect(WorkerRoutes.executionRoutes.length, 10);
  });

  test('WorkerApiException preserves sanitized request context', () {
    final error = WorkerApiException(
      method: 'POST',
      path: '/auth/challenges',
      statusCode: 404,
      code: 'HTTP_404',
      detail: 'Not Found',
    );
    expect(error.toString(), contains('method=POST'));
    expect(error.toString(), contains('path=/auth/challenges'));
    expect(error.toString(), contains('status=404'));
    expect(error.toString(), contains('code=HTTP_404'));
    expect(error.toString(), contains('detail=Not Found'));
    expect(error.isNotFound, isTrue);
  });
}
