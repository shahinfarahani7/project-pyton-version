import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/ui/worker_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mascotIsWorking', () {
    const working = {
      ExecutionPhase.preparing,
      ExecutionPhase.running,
      ExecutionPhase.checkpointing,
      ExecutionPhase.submitting,
      ExecutionPhase.cleaningUp,
    };

    for (final phase in ExecutionPhase.values) {
      test('${phase.name} -> ${working.contains(phase)}', () {
        expect(mascotIsWorking(phase), working.contains(phase));
      });
    }
  });

  group('MascotStateMachine', () {
    test('starts asleep when idle and working when busy', () {
      expect(MascotStateMachine(working: false).state, MascotState.asleep);
      expect(MascotStateMachine(working: true).state, MascotState.working);
    });

    test('stopping work winds down, naps, then stays asleep', () {
      final machine = MascotStateMachine(working: true);

      expect(machine.setWorking(false), isTrue);
      expect(machine.state, MascotState.windingDown);
      expect(machine.clipFinished(), isTrue);
      expect(machine.state, MascotState.napping);
      expect(machine.clipFinished(), isTrue);
      expect(machine.state, MascotState.asleep);
      expect(machine.clipFinished(), isFalse);
      expect(machine.setWorking(false), isFalse);
      expect(machine.state, MascotState.asleep);
    });

    test('a new task interrupts any rest state', () {
      for (final restClips in [0, 1, 2]) {
        final machine = MascotStateMachine(working: true)..setWorking(false);
        for (var i = 0; i < restClips; i++) {
          machine.clipFinished();
        }
        expect(machine.setWorking(true), isTrue, reason: 'after $restClips rest clips');
        expect(machine.state, MascotState.working);
      }
    });

    test('looping working clip never finishes on its own', () {
      final machine = MascotStateMachine(working: true);
      expect(machine.clipFinished(), isFalse);
      expect(machine.state, MascotState.working);
    });

    test('skipTransitions jumps straight to asleep but keeps working', () {
      final resting = MascotStateMachine(working: true)..setWorking(false);
      expect(resting.skipTransitions(), isTrue);
      expect(resting.state, MascotState.asleep);

      final busy = MascotStateMachine(working: true);
      expect(busy.skipTransitions(), isFalse);
      expect(busy.state, MascotState.working);
    });
  });

  group('WorkerMascotAnimation', () {
    String shownStill(WidgetTester tester) {
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as AssetImage).assetName;
    }

    Future<void> pumpMascot(WidgetTester tester, {required bool working, bool reduceMotion = false}) {
      return tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Center(child: WorkerMascotAnimation(working: working)),
        ),
      );
    }

    testWidgets('shows the still for its state before frames decode', (tester) async {
      await pumpMascot(tester, working: false);
      expect(shownStill(tester), mascotAsleepStill);
      expect(find.bySemanticsLabel('FibonAI mascot resting'), findsOneWidget);

      await pumpMascot(tester, working: true);
      expect(shownStill(tester), mascotWorkingStill);
      expect(find.bySemanticsLabel('FibonAI mascot running a task'), findsOneWidget);
    });

    testWidgets('with animations disabled, stopping work goes straight to asleep', (tester) async {
      await pumpMascot(tester, working: true, reduceMotion: true);
      expect(shownStill(tester), mascotWorkingStill);

      await pumpMascot(tester, working: false, reduceMotion: true);
      expect(shownStill(tester), mascotAsleepStill);
      expect(find.bySemanticsLabel('FibonAI mascot resting'), findsOneWidget);
    });

    testWidgets('every mascot asset is bundled', (tester) async {
      expect(mascotAssets, hasLength(6));
      expect(mascotAssets, contains('assets/mascot/sleep_loop.webp'));
      for (final asset in mascotAssets) {
        final data = await tester.runAsync(() => rootBundle.load(asset));
        expect(data!.lengthInBytes, greaterThan(0), reason: asset);
      }
    });
  });
}
