import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo/demo_activities.dart';
import '../engine/activity.dart';
import '../engine/activity_stack.dart';
import '../features/timer/timer_activity.dart';
import '../features/timer/timer_controller.dart';
import '../providers/audio_route_provider.dart';
import '../providers/battery_activity.dart';
import '../providers/battery_provider.dart';
import '../providers/now_playing_activity.dart';
import '../providers/now_playing_provider.dart';
import '../providers/now_playing_visibility_gate.dart';
import 'island_window_channel.dart';
import 'motion.dart';
import 'pill_geometry.dart';

/// The Island itself: one collapsed↔hover↔expanded↔interactive↔collapse
/// state machine (§00), rendering whatever the Activity Stack's top entry
/// currently is. This is the Phase 1 spike target — proving the shell and
/// engine work end-to-end on fake activities before any real provider exists.
class IslandShell extends StatefulWidget {
  const IslandShell({super.key});

  @override
  State<IslandShell> createState() => _IslandShellState();
}

class _IslandShellState extends State<IslandShell> with SingleTickerProviderStateMixin {
  static const Size _collapsedSize = Size(253, 41);
  static const Size _expandedSize = Size(360, 140);

  static const Duration _autoCollapseDelay = Duration(seconds: 5);

  final ActivityStack _stack = ActivityStack();
  final FocusNode _focusNode = FocusNode(debugLabel: 'IslandShell');
  late final NowPlayingVisibilityGate _nowPlayingVisibility = NowPlayingVisibilityGate(
    hideAfterPaused: const Duration(minutes: 1),
    onHide: _refreshNowPlayingActivity,
  );

  // The native window resize follows an ease-out curve — fast growth early,
  // slow settle late — so deriving content opacity from the real, current
  // height (as this used to) made the cross-fade front-load into the first
  // fraction of the transition: it'd finish while the box was still gently
  // growing for the rest of the 700ms, reading as a fast, separate snap
  // rather than one smooth motion. An independently-clocked animation, same
  // duration, gives content its own paced fade — exactly how the color tint
  // above already handles this (see AnimatedContainer's `color` below).
  late final AnimationController _contentTransition = AnimationController(
    vsync: this,
    duration: IslandMotion.expansionDuration,
  );

  NotchGeometry? _screen;
  LifecycleState _state = LifecycleState.collapsed;
  Timer? _autoCollapseTimer;
  StreamSubscription<BatterySnapshot>? _batterySubscription;
  StreamSubscription<NowPlayingSnapshot?>? _nowPlayingSubscription;
  StreamSubscription<AudioRouteSnapshot?>? _audioRouteSubscription;
  TimerController? _timerController;
  NowPlayingSnapshot? _lastNowPlaying;
  AudioRouteSnapshot? _lastAudioRoute;

  // _targetContentSize flips to _collapsedSize the instant _collapse() sets
  // _state to `collapsing` — synchronous, no animation. _contentTransition's
  // fade-out is not: it takes the full 700ms to reach 0. Using
  // _targetContentSize directly as the expanded overlay's box during that
  // window sized it for the *collapsed* pill while still trying to render
  // full expanded content — a RenderFlex overflow. This holds the last real
  // expanded/call size so the fading-out overlay keeps its correct canvas
  // until the fade (not just the state flag) actually finishes.
  Size _lastExpandedContentSize = _expandedSize;

  @override
  void initState() {
    super.initState();
    _stack.addListener(_onStackChanged);
    // Any click that lands outside this window — the window IS the pill, so
    // that's any click elsewhere on the screen — should dismiss an
    // open-but-not-interactive pill, same as it timing out on its own.
    IslandWindowChannel.setOutsideClickHandler(_handleOutsideClick);
    // Connecting/disconnecting a display (notched MacBook <-> external
    // monitor) or a resolution change lands here live — no restart needed.
    IslandWindowChannel.setScreenChangeHandler(_handleScreenChange);
    // Hardware media keys, reported regardless of window focus (see
    // NowPlayingChannel.swift) — only acted on while Now Playing is
    // actually the visible activity; see _handleMediaKey.
    NowPlayingProvider.setMediaKeyHandler(_handleMediaKey);
    _bootstrap();
  }

  @override
  void dispose() {
    _stack.removeListener(_onStackChanged);
    IslandWindowChannel.setOutsideClickHandler(null);
    IslandWindowChannel.setScreenChangeHandler(null);
    NowPlayingProvider.setMediaKeyHandler(null);
    _focusNode.dispose();
    _contentTransition.dispose();
    _autoCollapseTimer?.cancel();
    _nowPlayingVisibility.dispose();
    _batterySubscription?.cancel();
    _nowPlayingSubscription?.cancel();
    _audioRouteSubscription?.cancel();
    _timerController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final screen = await IslandWindowChannel.notchGeometry();

    // Real Now Playing only appears once something is actually playing
    // somewhere — unlike Battery, there's no "always register a default"
    // case here, and no recency race to guard against: two real providers
    // trading the top slot by whichever last became relevant is the
    // intended behavior (§03), not a bug to defend against like the old
    // fake-demo-vs-Battery race was.
    _nowPlayingSubscription = NowPlayingProvider.updates.listen((snapshot) {
      _lastNowPlaying = snapshot;
      _refreshNowPlayingActivity();
    });
    // A second, independent provider (CoreAudio) — only relevant to
    // re-render Now Playing's "via AirPods Pro" line, never gates whether
    // Now Playing itself is registered.
    _audioRouteSubscription = AudioRouteProvider.updates.listen((route) {
      _lastAudioRoute = route;
      _refreshNowPlayingActivity();
    });

    _batterySubscription = BatteryProvider.updates.listen(
      (snapshot) => _stack.register(buildBatteryActivity(
        snapshot,
        onSimulateCall: _simulateIncomingCall,
        onStartTimer: _startTimer,
      )),
    );

    if (!mounted) return;
    setState(() => _screen = screen);
    await _applyFrame(animated: false);
  }

  /// Now Playing's registration is gated on [_lastNowPlaying] plus the
  /// paused-hide hysteresis below — audio-route updates just refresh what's
  /// already showing, they never cause Now Playing to appear or disappear
  /// on their own.
  void _refreshNowPlayingActivity() {
    final snapshot = _lastNowPlaying;
    if (snapshot == null) {
      _nowPlayingVisibility.reset();
      _stack.remove('now-playing');
      return;
    }

    _nowPlayingVisibility.update(isPlaying: snapshot.isPlaying);
    if (_nowPlayingVisibility.isHidden) {
      _stack.remove('now-playing');
      return;
    }

    _stack.register(buildNowPlayingActivity(
      snapshot,
      audioRoute: _lastAudioRoute,
      onControlPressed: _startAutoCollapseTimer,
    ));
  }

  void _onStackChanged() => setState(() {});

  void _simulateIncomingCall() {
    _autoCollapseTimer?.cancel();
    _stack.register(buildIncomingCallDemoActivity(onResolve: _resolveIncomingCall));
    setState(() => _state = LifecycleState.interactive);
    IslandWindowChannel.setInteractive(true);
    _focusNode.requestFocus();
    // A P0/P1 activity "renders immediately, regardless of stack depth"
    // (§03) — snapped to full opacity, not faded in, since this is an
    // interruption, not a leisurely reveal. If already expanded this is a
    // no-op; if collapsed, content is instantly there while the box still
    // animates its resize (unchanged, existing behavior).
    _contentTransition.value = 1.0;
    _applyFrame(animated: true);
  }

  void _resolveIncomingCall() {
    _stack.remove('fake-call-demo');
    // Whatever's now on top (the ambient activity, unchanged since it was
    // suspended) is what renders next — nothing was torn down to get here.
    // Stays interactive/focused: expanded already keeps keyboard shortcuts
    // (space, media keys) live for whatever's showing now.
    setState(() => _state = LifecycleState.expanded);
    _startAutoCollapseTimer();
    _applyFrame(animated: true);
  }

  void _startTimer() {
    _timerController?.dispose();
    final controller = TimerController(const Duration(minutes: 1));
    _timerController = controller;
    controller.addListener(() {
      if (controller.isComplete) _handleTimerComplete(controller);
    });
    _stack.register(buildTimerActivity(controller: controller, onCancel: _cancelTimer));
  }

  void _cancelTimer() {
    _stack.remove('timer');
    _timerController?.dispose();
    _timerController = null;
    _startAutoCollapseTimer(); // cancelling is itself a relevant interaction
  }

  void _handleTimerComplete(TimerController controller) {
    // Same controller instance throughout — completion is a transition in
    // what's registered, not a teardown-and-recreate.
    if (_timerController != controller) return;
    _stack.remove('timer');
    _stack.register(buildTimerCompleteActivity());
    controller.dispose();
    _timerController = null;
  }

  void _handleScreenChange(NotchGeometry screen) {
    setState(() => _screen = screen);
    // A display swap isn't a UI-state transition — snap straight to the
    // correct spot rather than playing the expand/collapse motion for it.
    _applyFrame(animated: false);
  }

  // Hover is cosmetic only here — a mouse-over affordance, not a trigger.
  // Expansion happens on click; see _handleTap.
  void _handleHoverEnter() {
    if (_state == LifecycleState.collapsed) {
      setState(() => _state = LifecycleState.hover);
    }
  }

  void _handleHoverExit() {
    if (_state == LifecycleState.hover) {
      setState(() => _state = LifecycleState.collapsed);
    }
  }

  void _handleTap() {
    if (_stack.top?.priority == ActivityPriority.p1Immediate) return; // priority already owns the surface
    if (_state == LifecycleState.collapsed || _state == LifecycleState.hover) {
      setState(() => _state = LifecycleState.expanded);
      // Expanded is "deliberate enough" to take keyboard focus for its own
      // shortcuts (space, media keys) — .nonactivatingPanel means this still
      // never brings Islandia itself to the front over whatever app the
      // user was in.
      IslandWindowChannel.setInteractive(true);
      _focusNode.requestFocus();
      _contentTransition.forward();
      _applyFrame(animated: true);
      _startAutoCollapseTimer();
    }
  }

  void _handleOutsideClick() {
    if (_state == LifecycleState.expanded) {
      _collapse();
    }
  }

  /// A press that's relevant to whatever activity is currently showing
  /// (a playback control, cancelling a timer, a media key) — resets the
  /// auto-collapse clock, same as freshly expanding does. An irrelevant key
  /// (any regular letter) or a media key press while collapsed does not.
  void _startAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(_autoCollapseDelay, () {
      if (_state == LifecycleState.expanded) _collapse();
    });
  }

  /// Space toggles play/pause for Now Playing specifically — only reachable
  /// while this window is actually key (expanded/interactive; see
  /// _handleTap), so it can never compete with typing in another app the
  /// way a global keyboard monitor would.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_stack.top?.id != 'now-playing') return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.space) return KeyEventResult.ignored;
    NowPlayingProvider.send(NowPlayingProvider.commandTogglePlayPause);
    _startAutoCollapseTimer();
    return KeyEventResult.handled;
  }

  /// Hardware media keys arrive here regardless of what's currently showing
  /// or focused (see NowPlayingChannel.swift). macOS already delivers the
  /// raw key press straight to whatever app owns the current Now Playing
  /// session — that's why F7/F8/F9 already control Spotify/Music/a browser
  /// tab with no Islandia involvement at all, on any Mac. Also calling
  /// NowPlayingProvider.send(...) here would issue a *second*, redundant
  /// command through MediaRemote on top of that — for a toggle, one that
  /// silently undoes itself (resume, then immediately re-pause), which is
  /// exactly the bug this replaced. So this only ever resets the
  /// auto-collapse clock — a real interaction, just not one Islandia needs
  /// to also act on — while Now Playing is actually the visible activity.
  void _handleMediaKey(String action) {
    if (_stack.top?.id != 'now-playing') return;
    if (_state != LifecycleState.expanded && _state != LifecycleState.interactive) return;
    _startAutoCollapseTimer();
  }

  void _collapse() {
    _autoCollapseTimer?.cancel();
    IslandWindowChannel.setInteractive(false);
    _focusNode.unfocus();
    _contentTransition.reverse();
    setState(() => _state = LifecycleState.collapsing);
    _applyFrame(animated: true).then((_) {
      if (mounted) setState(() => _state = LifecycleState.collapsed);
    });
  }

  /// The size this state/activity combination is heading to (or already at).
  /// One fixed expanded size for every activity — a call, Now Playing,
  /// battery, a timer — rather than each activity picking its own; the pill
  /// never changes footprint just because a different activity took the top
  /// slot. Shared by [_applyFrame] (tells the native window what to animate
  /// to) and [build] (tells the content what canvas to lay itself out on) so
  /// the two can never disagree about what "expanded" currently means.
  Size get _targetContentSize {
    return switch (_state) {
      LifecycleState.collapsed || LifecycleState.hover || LifecycleState.collapsing => _collapsedSize,
      LifecycleState.expanded || LifecycleState.interactive => _expandedSize,
    };
  }

  Future<void> _applyFrame({required bool animated}) async {
    final screen = _screen;
    if (screen == null) return;
    final targetSize = _targetContentSize;
    final collapsed = collapsedFrame(screen, _collapsedSize);
    final frame = targetSize == _collapsedSize ? collapsed : expandedFrame(collapsed, targetSize);
    await IslandWindowChannel.animateToFrame(
      x: frame.left,
      y: frame.top,
      width: frame.width,
      height: frame.height,
      duration: animated ? IslandMotion.expansionDuration : Duration.zero,
    );
  }

  /// A generic (not Now-Playing-specific) cross-fade for every activity:
  /// collapsed content fades out while expanded content fades in, both
  /// overlaid in a Stack, so elements exclusive to one side ease in/out
  /// instead of the old behavior — expandedBuilder's full layout rendering
  /// at full opacity the instant you tap, with only the growing clip mask
  /// gradually *uncovering* already-finished content. Not a true
  /// shared-element morph (the artwork doesn't slide/grow from its
  /// collapsed position to its expanded one — that would need each
  /// activity's content rewritten as one Stack with lerped Positioned
  /// geometry, a bigger follow-up), but it replaces "sudden appearance"
  /// with an actual transition.
  Widget _crossFadedContent(BuildContext context, Activity top, double t, Size contentSize) {
    final showCollapsed = t < 1.0;
    final showExpanded = t > 0.0;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        if (showCollapsed)
          Opacity(
            opacity: 1.0 - t,
            child: _sizedOverlay(top.collapsedBuilder(context, _state), _collapsedSize),
          ),
        if (showExpanded)
          Opacity(
            opacity: t,
            child: _sizedOverlay(top.expandedBuilder(context, _state), contentSize),
          ),
      ],
    );
  }

  // The window (the ClipRRect's actual size in `build`) is mid-resize for
  // the whole duration of a transition — anywhere from collapsed size up to
  // `contentSize`. Content still needs to be laid out at its full, correct
  // size the entire time, or a Column with a Spacer() gets asked to fit
  // into a box smaller than its own children and throws. OverflowBox gives
  // it that full canvas regardless of the current (smaller) window size.
  Widget _sizedOverlay(Widget child, Size size) {
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: 0,
      minHeight: 0,
      maxWidth: size.width,
      maxHeight: size.height,
      child: SizedBox(width: size.width, height: size.height, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = _stack.top;
    final canExpandOnTap = _state == LifecycleState.collapsed || _state == LifecycleState.hover;
    final targetSize = _targetContentSize;
    if (targetSize != _collapsedSize) _lastExpandedContentSize = targetSize;
    final contentSize = _lastExpandedContentSize;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => _handleHoverEnter(),
        onExit: (_) => _handleHoverExit(),
        child: Semantics(
          hint: canExpandOnTap ? 'Double tap to expand' : null,
          child: GestureDetector(
            onTap: _handleTap,
            // The native window resize IS the size animation (see
            // MainFlutterWindow.setPillFrame) — it has its own clock and
            // curve. Animating the corner radius on a *second*, independent
            // Flutter-side clock let the two drift relative to each other
            // mid-transition (a visibly square box whose corners rounded off a
            // beat late), so ClipRRect's radius is still computed straight
            // from the real, current constraints every frame, never tweened.
            // Content opacity is different: deriving it from the box's real
            // (ease-out-curved) height made the cross-fade front-load into
            // the first fraction of the transition and finish early — a
            // *geometry* mismatch there caused a visible layout bug, but a
            // *pacing* mismatch is much more forgiving, so content gets its
            // own independently-clocked animation instead (_contentTransition),
            // same as the color tint below already had.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final radius = math.min(24.0, math.min(constraints.maxWidth, constraints.maxHeight) / 2);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: AnimatedBuilder(
                    animation: _contentTransition,
                    builder: (context, _) {
                      final contentT = IslandMotion.expansionCurve.transform(_contentTransition.value);
                      return AnimatedContainer(
                        duration: IslandMotion.expansionDuration,
                        curve: IslandMotion.expansionCurve,
                        color: top?.priority == ActivityPriority.p1Immediate ? const Color(0xFF3A1414) : Colors.black,
                        alignment: Alignment.topCenter,
                        child: top == null
                            ? const SizedBox.shrink()
                            : _crossFadedContent(context, top, contentT, contentSize),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
