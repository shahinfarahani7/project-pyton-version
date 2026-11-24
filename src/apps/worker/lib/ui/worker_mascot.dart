import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../runtime/execution_status.dart';

/// Mascot states in the order they play when work stops.
enum MascotState { working, windingDown, napping, asleep }

/// Whether the mascot should show the working (running) animation for [phase].
bool mascotIsWorking(ExecutionPhase phase) => switch (phase) {
      ExecutionPhase.preparing ||
      ExecutionPhase.running ||
      ExecutionPhase.checkpointing ||
      ExecutionPhase.submitting ||
      ExecutionPhase.cleaningUp =>
        true,
      ExecutionPhase.idle ||
      ExecutionPhase.waitingForAssignment ||
      ExecutionPhase.paused ||
      ExecutionPhase.failed ||
      ExecutionPhase.completed =>
        false,
    };

/// Decides which clip plays; the widget only renders the current [state].
class MascotStateMachine {
  MascotStateMachine({required bool working})
      : state = working ? MascotState.working : MascotState.asleep;

  MascotState state;

  /// Returns true when the state changed.
  bool setWorking(bool working) {
    final next = working
        ? MascotState.working
        : (state == MascotState.working ? MascotState.windingDown : state);
    return _moveTo(next);
  }

  /// Called when a play-once clip reaches its last frame. Returns true when the state changed.
  bool clipFinished() => _moveTo(switch (state) {
        MascotState.windingDown => MascotState.napping,
        MascotState.napping => MascotState.asleep,
        MascotState.working || MascotState.asleep => state,
      });

  /// Skips transition clips (used when animations are disabled). Returns true when the state changed.
  bool skipTransitions() => _moveTo(switch (state) {
        MascotState.windingDown || MascotState.napping => MascotState.asleep,
        MascotState.working || MascotState.asleep => state,
      });

  bool _moveTo(MascotState next) {
    if (next == state) {
      return false;
    }
    state = next;
    return true;
  }
}

class _MascotClip {
  const _MascotClip(this.asset, {required this.loop});

  final String asset;
  final bool loop;
}

const _clips = <MascotState, _MascotClip>{
  MascotState.working: _MascotClip('assets/mascot/run_loop.webp', loop: true),
  MascotState.windingDown: _MascotClip('assets/mascot/run_to_sleep.webp', loop: false),
  MascotState.napping: _MascotClip('assets/mascot/nap.webp', loop: false),
  MascotState.asleep: _MascotClip('assets/mascot/sleep_loop.webp', loop: true),
};

const mascotWorkingStill = 'assets/mascot/working.webp';
const mascotAsleepStill = 'assets/mascot/asleep.webp';

/// Every asset the mascot can load.
final List<String> mascotAssets = [
  for (final clip in _clips.values) clip.asset,
  mascotWorkingStill,
  mascotAsleepStill,
];

const _fallbackFrameDuration = Duration(milliseconds: 42);

/// Animated FibonAI mascot: runs while a task executes, winds down and naps when work stops,
/// then breathes in a sleep loop until the next task.
///
/// Clips are animated WebP decoded one frame at a time, so only the current frame is held in memory.
/// With animations disabled (accessibility setting) it shows a still for the current state.
class WorkerMascotAnimation extends StatefulWidget {
  const WorkerMascotAnimation({
    super.key,
    required this.working,
    this.height = 140,
  });

  final bool working;
  final double height;

  static const aspectRatio = 528 / 320;

  @override
  State<WorkerMascotAnimation> createState() => _WorkerMascotAnimationState();
}

class _WorkerMascotAnimationState extends State<WorkerMascotAnimation>
    with SingleTickerProviderStateMixin {
  late final MascotStateMachine _machine = MascotStateMachine(working: widget.working);
  late final Ticker _ticker = createTicker(_onTick);
  ui.Codec? _codec;
  ui.Image? _frame;
  int _framesShown = 0;
  Duration _nextFrameAt = Duration.zero;
  bool _decoding = false;
  int _generation = 0;
  bool? _animate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate != _animate) {
      _animate = animate;
      _startClip();
    }
  }

  @override
  void didUpdateWidget(WorkerMascotAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_machine.setWorking(widget.working)) {
      _startClip();
    }
  }

  @override
  void dispose() {
    _generation++;
    _ticker.dispose();
    _codec?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  /// Synchronous part only mutates fields: callers are lifecycle methods followed by a build,
  /// or [_onTick], which calls setState itself.
  Future<void> _startClip() async {
    final generation = ++_generation;
    _ticker.stop();
    _decoding = false;
    _codec?.dispose();
    _codec = null;

    if (_animate != true) {
      _machine.skipTransitions();
      _frame?.dispose();
      _frame = null;
      return;
    }
    final clip = _clips[_machine.state];
    if (clip == null) {
      return;
    }
    try {
      final data = await rootBundle.load(clip.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _codec = codec;
      _framesShown = 0;
      _nextFrameAt = Duration.zero;
      _ticker.start();
    } catch (error, stack) {
      _reportError(error, stack);
    }
  }

  void _onTick(Duration elapsed) {
    final codec = _codec;
    final clip = _clips[_machine.state];
    if (codec == null || clip == null || _decoding || elapsed < _nextFrameAt) {
      return;
    }
    if (!clip.loop && _framesShown >= codec.frameCount) {
      _ticker.stop();
      if (_machine.clipFinished()) {
        setState(() {});
        _startClip();
      }
      return;
    }
    _decoding = true;
    final generation = _generation;
    codec.getNextFrame().then<void>(
      (ui.FrameInfo info) {
        if (!mounted || generation != _generation) {
          info.image.dispose();
          return;
        }
        _decoding = false;
        _framesShown++;
        _nextFrameAt += info.duration > Duration.zero ? info.duration : _fallbackFrameDuration;
        _setFrame(info.image);
      },
      onError: (Object error, StackTrace stack) {
        if (generation != _generation) {
          return;
        }
        _decoding = false;
        _ticker.stop();
        _reportError(error, stack);
      },
    );
  }

  void _setFrame(ui.Image image) {
    final previous = _frame;
    setState(() => _frame = image);
    previous?.dispose();
  }

  void _reportError(Object error, StackTrace stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'worker mascot',
      context: ErrorDescription('while playing the mascot animation'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final working = _machine.state == MascotState.working;
    final frame = _frame;
    return Semantics(
      image: true,
      textDirection: TextDirection.ltr,
      label: working ? 'FibonAI mascot running a task' : 'FibonAI mascot resting',
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height,
          child: AspectRatio(
            aspectRatio: WorkerMascotAnimation.aspectRatio,
            child: frame != null
                ? RawImage(image: frame, fit: BoxFit.contain, filterQuality: FilterQuality.medium)
                : Image.asset(
                    working ? mascotWorkingStill : mascotAsleepStill,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}
