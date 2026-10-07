/// Canonical worker API route templates from edgemint-worker-api v2.1.0.
abstract final class WorkerRoutes {
  static const String createChallenge = '/auth/challenges';
  static const String registerDevice = '/workers/register';
  static const String refreshSession = '/sessions:refresh';
  static const String workerPreferences = '/worker-preferences';

  static String workerBenchmark(String workerId) => '/workers/$workerId/benchmark';
  static String workerHeartbeat(String workerId) => '/workers/$workerId/heartbeat';
  static String modelManifest(String modelVersionId) => '/models/$modelVersionId/manifest';
  static String reportModelInstall(String modelVersionId) => '/models/$modelVersionId:report-install';

  static const nextAssignment = '/assignments:next';
  static const assignmentInboxBootstrap = '/assignments:inboxBootstrap';
  static String renewAssignment(String assignmentId) => '/assignments/$assignmentId:renew';
  static String reportAssignmentStarted(String assignmentId) => '/assignments/$assignmentId:started';
  static String assignmentCancellation(String assignmentId) =>
      '/assignments/$assignmentId/cancellation';
  static String progressAssignment(String assignmentId) => '/assignments/$assignmentId:progress';
  static String checkpointAssignment(String assignmentId) => '/assignments/$assignmentId:checkpoint';
  static String completeAssignment(String assignmentId) => '/assignments/$assignmentId:complete';
  static String failAssignment(String assignmentId) => '/assignments/$assignmentId:fail';
  static String confirmPhysicalStop(String assignmentId) => '/assignments/$assignmentId:confirmStop';
  static String abandonAssignment(String assignmentId) => '/assignments/$assignmentId:abandon';

  static const enrollmentRoutes = <String>[
    createChallenge,
    registerDevice,
    refreshSession,
    workerPreferences,
  ];

  static const modelDeliveryRoutes = <String>[
    '/models/mdv_example/manifest',
    '/models/mdv_example:report-install',
  ];

  static const executionRoutes = <String>[
    nextAssignment,
    assignmentInboxBootstrap,
    '/assignments/asg_example:renew',
    '/assignments/asg_example:started',
    '/assignments/asg_example:progress',
    '/assignments/asg_example:checkpoint',
    '/assignments/asg_example:complete',
    '/assignments/asg_example:fail',
    '/assignments/asg_example:confirmStop',
    '/assignments/asg_example:abandon',
  ];
}
