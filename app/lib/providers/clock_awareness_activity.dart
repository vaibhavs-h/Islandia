import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/activity.dart';
import 'clock_awareness_provider.dart';
import 'duration_format.dart';

/// Which of the two views [buildClockAwarenessActivity] should currently
/// show. A stopwatch running alongside a timer is the only case where these
/// compete for the same slot — see [selectClockAwarenessView].
enum ClockAwarenessView { stopwatch, timer }

/// How close to firing a running timer has to be before it preempts a
/// running stopwatch, even before the alarm actually sounds.
const Duration _timerPreemptWindow = Duration(seconds: 10);

/// Decides stopwatch vs timer for a given snapshot, given what was showing
/// a moment ago. Kept as its own pure function (no widgets, no Activity)
/// specifically so the handback rule is unit-testable without pumping a
/// widget tree: a timer within its last 10 seconds — or whose alarm is
/// still ringing, unresolved — takes the slot from a running stopwatch;
/// once the alarm stops ringing, the stopwatch (if still running) takes it
/// back. Outside of that contest, whichever of the two actually has
/// something running just shows on its own.
///
/// [wasShowing] only matters while a timer is ringing: the plist alone
/// cannot tell "still ringing" apart from "already dismissed" (confirmed
/// live — see ClockAlarmRingingWatcher's doc comment), so
/// [ClockAwarenessSnapshot.isAlarmRinging] is trusted as the sole source of
/// truth for that transition rather than re-deriving it from remaining time.
ClockAwarenessView? selectClockAwarenessView(ClockAwarenessSnapshot snapshot, ClockAwarenessView? wasShowing) {
  final soonest = snapshot.soonest;
  final hasStopwatch = snapshot.stopwatch != null;
  final timerInPreemptWindow = soonest != null && soonest.remaining <= _timerPreemptWindow;

  // isAlarmRinging implies a timer really did just fire — native
  // guarantees soonest stays non-null for as long as ringing does (see
  // ClockActivityChannel.emit()'s own doc comment) — but this only ever
  // renders that fact if there's actually a timer to render alongside it.
  // A bug here once registered the timer view with an empty timer list,
  // leaving the pill occupying the top slot while rendering nothing (a
  // plain black pill, no crash) instead of falling through and letting a
  // lower-priority activity show through.
  if (snapshot.isAlarmRinging && soonest != null) return ClockAwarenessView.timer;
  if (wasShowing == ClockAwarenessView.timer && soonest != null && !hasStopwatch) return ClockAwarenessView.timer;

  if (hasStopwatch) {
    return timerInPreemptWindow ? ClockAwarenessView.timer : ClockAwarenessView.stopwatch;
  }
  return soonest != null ? ClockAwarenessView.timer : null;
}

/// Real macOS Clock app awareness (§v1: timer + stopwatch). One activity id
/// for both views — they're two faces of the same ongoing "what's Clock
/// doing" fact, not two independent things competing for the stack, so a
/// stopwatch↔timer handback is a content swap within this activity rather
/// than one activity's priority beating another's.
///
/// [generation] is folded into the id — see island_shell.dart's
/// _refreshClockAwarenessActivity for why a fixed id alone would never
/// cross-fade the one transition (stopwatch↔timer) that needs it.
///
/// [onTimerPauseRequested] fires the instant the Pause button is tapped —
/// purely a signal to island_shell.dart's own _timerHeldByPause flag (see
/// its doc comment for the full design and the two earlier, buggier
/// designs it replaced: a data-override that got permanently stuck live,
/// then a short fixed-expiry version that let a stopwatch reclaim the view
/// slot too soon). While that flag is set, island_shell.dart forces the
/// timer view to stay selected regardless of what selectClockAwarenessView
/// would otherwise decide — the actual frozen *display* when the timer
/// then vanishes from live data lives entirely in _TimerExpanded's own
/// widget state below; this parameter is the one piece of the mechanism
/// island_shell.dart owns instead, since only it decides what view shows
/// at all.
///
/// [onTimerCancelRequested] and [onTimerResumeRequested] are the two ways
/// that hold ends early (the other being the view actually collapsing) —
/// both just clear the same flag.
Activity buildClockAwarenessActivity(
  ClockAwarenessSnapshot snapshot,
  ClockAwarenessView view, {
  required int generation,
  VoidCallback? onTimerPauseRequested,
  VoidCallback? onTimerCancelRequested,
  VoidCallback? onTimerResumeRequested,
}) {
  return Activity(
    id: 'clock-awareness-$generation',
    priority: ActivityPriority.p3Ambient,
    collapsedBuilder: (context, state) => _ClockAwarenessCollapsed(snapshot: snapshot, view: view),
    expandedBuilder: (context, state) => _ClockAwarenessExpanded(
      snapshot: snapshot,
      view: view,
      onTimerPauseRequested: onTimerPauseRequested,
      onTimerCancelRequested: onTimerCancelRequested,
      onTimerResumeRequested: onTimerResumeRequested,
    ),
  );
}

class _ClockAwarenessCollapsed extends StatelessWidget {
  const _ClockAwarenessCollapsed({required this.snapshot, required this.view});

  final ClockAwarenessSnapshot snapshot;
  final ClockAwarenessView view;

  @override
  Widget build(BuildContext context) {
    if (view == ClockAwarenessView.timer) {
      final timer = snapshot.soonest;
      if (timer == null) return const SizedBox.shrink();
      final title = timer.title.isEmpty ? 'Timer' : timer.title;
      // Once fired, "remaining" is whatever native last read a moment
      // before it hit zero (see ClockActivityChannel.emit()) — a number
      // frozen at or near 00:00 for the whole ringing window reads as
      // broken, not finished, so this shows the state in words instead.
      if (snapshot.isAlarmRinging) {
        return Semantics(
          label: '$title done.',
          excludeSemantics: true,
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('done', style: TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        );
      }
      final extra = snapshot.otherTimerCount;
      return Semantics(
        label: '$title, ${formatTimerDuration(timer.remaining)} remaining'
            '${extra > 0 ? ', and $extra other timer${extra == 1 ? '' : 's'} running' : ''}.',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatTimerDuration(timer.remaining),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]),
              ),
              if (extra > 0) ...[
                const SizedBox(width: 6),
                Text('+$extra', style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ],
            ],
          ),
        ),
      );
    }

    final stopwatch = snapshot.stopwatch;
    if (stopwatch == null) return const SizedBox.shrink();
    return _StopwatchTicker(
      stopwatch: stopwatch,
      builder: (context, elapsed) => Semantics(
        label: 'Stopwatch, ${formatStopwatchDuration(elapsed)} elapsed.',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text('Stopwatch', style: TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                formatStopwatchDuration(elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one part of this feature that needs to visibly tick faster than
/// native's 1Hz poll (see ClockActivityChannel.pollInterval) — centiseconds
/// only look like a real stopwatch if they're actually advancing between
/// polls, not re-displaying the same polled value for a whole second.
/// [builder] supplies the actual widget tree — the collapsed pill's single
/// centered row and the expanded card's icon-row-then-big-time layout are
/// different enough shapes that forcing them through one parameterized
/// widget was worse than just letting each own its layout, so this only
/// owns the ticker lifecycle, matching how now_playing_activity.dart
/// isolates its own ticking piece (_NowPlayingExpandedState) rather than
/// ticking the whole card.
class _StopwatchTicker extends StatefulWidget {
  const _StopwatchTicker({required this.stopwatch, required this.builder});

  final ClockRunningStopwatch stopwatch;
  final Widget Function(BuildContext context, Duration elapsed) builder;

  @override
  State<_StopwatchTicker> createState() => _StopwatchTickerState();
}

class _StopwatchTickerState extends State<_StopwatchTicker> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Fast enough that a real centisecond digit rollover (every 10ms) is
    // never more than one frame late — the two-digit field would otherwise
    // visibly stutter rather than count smoothly.
    _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.stopwatch.currentElapsed());
}

class _ClockAwarenessExpanded extends StatelessWidget {
  const _ClockAwarenessExpanded({
    required this.snapshot,
    required this.view,
    this.onTimerPauseRequested,
    this.onTimerCancelRequested,
    this.onTimerResumeRequested,
  });

  final ClockAwarenessSnapshot snapshot;
  final ClockAwarenessView view;
  final VoidCallback? onTimerPauseRequested;
  final VoidCallback? onTimerCancelRequested;
  final VoidCallback? onTimerResumeRequested;

  @override
  Widget build(BuildContext context) {
    if (view == ClockAwarenessView.timer) {
      // timer can genuinely be null here — a recently-requested pause is
      // exactly the case island_shell.dart keeps this Activity (and so
      // this widget) registered for even though live data has nothing
      // left to show (see _refreshClockAwarenessActivity). _TimerExpanded
      // is always constructed regardless, so its own State can remember
      // the last real timer it saw and decide whether to keep rendering
      // it — bailing out to SizedBox.shrink() here, before that widget
      // ever mounts, would have thrown away the one place that memory can
      // actually live.
      return _TimerExpanded(
        timer: snapshot.soonest,
        onCancelRequested: onTimerCancelRequested,
        onResumeRequested: onTimerResumeRequested,
        isRinging: snapshot.isAlarmRinging,
        otherTimerCount: snapshot.otherTimerCount,
        onPauseRequested: onTimerPauseRequested,
      );
    }

    final stopwatch = snapshot.stopwatch;
    if (stopwatch == null) return const SizedBox.shrink();
    return _StopwatchTicker(stopwatch: stopwatch, builder: (context, elapsed) => _StopwatchExpanded(stopwatch: stopwatch, elapsed: elapsed));
  }
}

/// Same role as [_StopwatchTicker] but for a countdown instead of an
/// elapsed clock — local ticking between native's 1Hz polls so the radial
/// ring visibly depletes smoothly rather than jumping once a second. A
/// countdown only needs whole-second precision in its own text (unlike the
/// stopwatch's centiseconds), but the *ring* still needs to move
/// continuously — a ring that only updates once a second reads as
/// stuttering in a way a once-a-second digit change doesn't, since a
/// circular arc's motion is much more perceptible than a digit swap.
class _TimerTicker extends StatefulWidget {
  const _TimerTicker({required this.timer, required this.builder});

  final ClockRunningTimer timer;
  final Widget Function(BuildContext context, Duration remaining, double progressFraction) builder;

  @override
  State<_TimerTicker> createState() => _TimerTickerState();
}

class _TimerTickerState extends State<_TimerTicker> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.timer.currentRemaining(), widget.timer.progressFraction());
}

/// Clock's own accent — matches its Pause button and (once wired here) the
/// progress bar's fill, confirmed against a live screenshot of Clock's own
/// Timer tab.
const _timerAccent = Color(0xFFFF9F0A);

/// Resume's own color — a distinct green, not Clock's own (Clock's button
/// stays the same orange for both Pause and Resume; this island's own
/// Resume state is deliberately different so the paused-vs-running
/// distinction reads at a glance without needing to read the label).
const _timerResumeAccent = Color(0xFF6BC96B);

/// The Timer expanded card — icon/name row, a big countdown, then a
/// horizontal depleting progress bar spanning the full width, then
/// Cancel/Pause buttons that drive the real Clock app (see
/// ClockAwarenessControl/ClockTimerController.swift) the same way the
/// Stopwatch card's Lap/Stop buttons do.
///
/// A circular ring was the first attempt here, but this card's available
/// space is much wider than it is tall — a true circle can only ever be as
/// large as the shorter (vertical) dimension, which left a small ring
/// stranded in a lot of dead horizontal space either side of it. A
/// horizontal bar has no such constraint: it's exactly as wide as the card
/// itself, using the space a ring couldn't.
/// [timer] can be null — see _ClockAwarenessExpanded's own doc comment for
/// why this is constructed even when live data has nothing to show right
/// now (a recently-requested pause bridging the gap before Clock's plist
/// catches up). This is a StatefulWidget specifically so that gap has
/// somewhere to live: [_TimerExpandedState] remembers the last real
/// [timer] it was given and its own local "paused" flag, entirely local to
/// this widget instance — no data override anywhere upstream, and no
/// explicit clearing code needed either, since Flutter's own lifecycle
/// discards this state the moment island_shell.dart legitimately swaps to
/// a different Activity (a stopwatch taking over, a different timer
/// becoming soonest, or genuinely nothing left at all once the freeze
/// window elapses). An earlier version tried to solve this one layer up,
/// in island_shell.dart's own snapshot data — confirmed live to produce
/// three separate real bugs from one test sequence, the worst of which
/// left a canceled timer permanently stuck on screen, immune even to a
/// real Cancel from Clock itself, until a full app restart. Keeping the
/// memory local to the one widget that actually needs it means there is
/// nothing left to get stuck: this widget either keeps existing (and its
/// own state is exactly as long-lived as that) or it's disposed along
/// with everything it remembered.
class _TimerExpanded extends StatefulWidget {
  const _TimerExpanded({
    required this.timer,
    required this.isRinging,
    required this.otherTimerCount,
    this.onPauseRequested,
    this.onCancelRequested,
    this.onResumeRequested,
  });

  final ClockRunningTimer? timer;
  final bool isRinging;
  final int otherTimerCount;

  /// Fired the instant Pause is tapped — signals island_shell.dart's own
  /// short-lived flag (see its own doc comment) that a pause was just
  /// requested, so it keeps this Activity registered instead of removing
  /// it the moment [timer] next reads as null. Purely a signal; this
  /// widget's own state does the actual remembering and rendering.
  final VoidCallback? onPauseRequested;

  /// Fired the instant Cancel is tapped — clears island_shell.dart's own
  /// hold-the-timer-view flag (see its own doc comment) immediately, so a
  /// cancel while paused doesn't leave the timer view forcibly selected
  /// once nothing legitimate remains to show.
  final VoidCallback? onCancelRequested;

  /// Fired the instant Resume is tapped — same idea as [onCancelRequested]:
  /// clears island_shell.dart's hold, since a resumed timer should compete
  /// for its view slot on its own real merits again, not stay artificially
  /// pinned by a pause that's no longer in effect.
  final VoidCallback? onResumeRequested;

  @override
  State<_TimerExpanded> createState() => _TimerExpandedState();
}

class _TimerExpandedState extends State<_TimerExpanded> with _ClockCommandFeedback<_TimerExpanded> {
  ClockRunningTimer? _lastRealTimer;

  /// True from the instant Pause is tapped until either a genuinely fresh
  /// [ClockRunningTimer] arrives (resumed, or a different timer entirely —
  /// either way, real new data always wins and clears this) or this
  /// widget itself is disposed (island_shell.dart moved on to something
  /// else, which also means this frozen memory no longer matters).
  bool _isPaused = false;

  @override
  void didUpdateWidget(_TimerExpanded oldWidget) {
    super.didUpdateWidget(oldWidget);
    final timer = widget.timer;
    if (timer != null) {
      _lastRealTimer = timer;
      // Fresh real data — whether this is the same timer resumed or a
      // different one becoming soonest, either way it's no longer the
      // frozen, paused state this widget's own button put it in.
      _isPaused = false;
    }
  }

  void _handlePauseButtonTap() {
    // Regression: an earlier version let this run while widget.isRinging
    // was true — a *ringing* timer has no live Clock Timers-tab UI to
    // pause at all (it's a fired alert, not a running countdown), so
    // ClockTimerController's own AX press found nothing real to act on,
    // while this widget still entered its local frozen-paused state using
    // the ringing timer's own (already-fired, effectively meaningless)
    // data — with no way out: Resume had nothing real to resume either.
    // Confirmed live: this produced exactly the "stuck forever" report
    // that motivated this whole redesign in the first place. The build()
    // guard now hides this button entirely while ringing, but this check
    // stays too — no path through this method should ever be able to
    // freeze on ringing data, whether or not the button that reaches it
    // stays hidden.
    if (widget.isRinging) return;
    final timer = widget.timer ?? _lastRealTimer;
    if (timer == null) return;
    setState(() {
      // A genuine freeze, not just an alias to the live object — timer's
      // own `asOf` is still whatever native last polled it at, and
      // currentRemaining()/progressFraction() both extrapolate forward
      // from that using wall-clock time regardless of _isPaused. Storing
      // `timer` directly here (an earlier version did exactly that) meant
      // the countdown and progress bar kept silently advancing on every
      // later rebuild — confirmed live: the bar visibly kept draining
      // while "paused" showed Resume. Capturing currentRemaining() now,
      // as a plain static value, with asOf explicitly omitted (not
      // `timer.asOf` — that's the one field that must NOT carry over),
      // is what actually makes the countdown hold still.
      _lastRealTimer = ClockRunningTimer(id: timer.id, remaining: timer.currentRemaining(), title: timer.title, duration: timer.duration);
      _isPaused = true;
    });
    widget.onPauseRequested?.call();
    ClockAwarenessControl.pauseTimer().then(_reportResult);
  }

  void _handleResumeButtonTap() {
    setState(() => _isPaused = false);
    widget.onResumeRequested?.call();
    ClockAwarenessControl.pauseTimer().then(_reportResult);
  }

  void _handleCancelButtonTap() {
    // Always clear both the freeze flag AND the remembered timer itself on
    // Cancel — build()'s fallback now reads _lastRealTimer any time
    // widget.timer is null, not just while _isPaused (see build()'s own
    // comment on why: that was gated on _isPaused specifically to avoid
    // this exact problem, then hit a *different*, confirmed-live bug
    // instead — a black flash on Resume, because _isPaused clears before
    // the next real snapshot arrives). Leaving _lastRealTimer set here
    // would mean island_shell.dart's snapshot correctly has nothing left
    // to show once Clock's cancel lands, but this widget would keep
    // rendering that stale memory forever anyway, via the same fallback
    // that's now unconditional.
    setState(() {
      _isPaused = false;
      _lastRealTimer = null;
    });
    widget.onCancelRequested?.call();
    ClockAwarenessControl.cancelTimer().then(_reportResult);
  }

  @override
  Widget build(BuildContext context) {
    // Prefer live data; fall back to the last remembered timer whenever
    // live data has nothing *this frame* — not gated on _isPaused, which
    // is exactly the bug this used to have: _handleResumeButtonTap clears
    // _isPaused synchronously in the same tap that requests a real Resume
    // from Clock, but the next live snapshot (island_shell.dart's next
    // poll tick, via didUpdateWidget) hasn't arrived yet — for that one
    // frame, widget.timer is still null and _isPaused is already false,
    // so gating the fallback on _isPaused meant neither source had
    // anything to show and this returned SizedBox.shrink(), a real,
    // confirmed-live black flash on every Resume tap (frame-captured via
    // temporary debug logging: widget.timer=null _isPaused=false
    // _lastRealTimer=<still valid> at the exact frame after Resume).
    // _lastRealTimer is never stale garbage here regardless of _isPaused's
    // value — it's only ever written by a real pause (frozen at tap time)
    // or a real fresh arrival (didUpdateWidget), so falling back to it on
    // *any* live-data gap, not just a paused one, is strictly safer than
    // rendering nothing: a canceled timer still correctly renders nothing
    // once _lastRealTimer itself is cleared (see _handleCancelButtonTap —
    // the one place besides a fresh real arrival that ever writes to
    // _lastRealTimer).
    final timer = widget.timer ?? _lastRealTimer;
    if (timer == null) return const SizedBox.shrink();

    final title = timer.title.isEmpty ? 'Timer' : timer.title;
    final isRinging = widget.isRinging;
    final otherTimerCount = widget.otherTimerCount;
    return Semantics(
      label: isRinging
          ? '$title done.'
          : '$title, ${formatTimerDuration(timer.remaining)} remaining'
              '${otherTimerCount > 0 ? ', and $otherTimerCount other timer${otherTimerCount == 1 ? '' : 's'} running' : ''}.',
      excludeSemantics: true,
      liveRegion: isRinging,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: isRinging
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer, color: Colors.white, size: 22),
                              const SizedBox(height: 4),
                              Flexible(
                                child: Text(
                                  title,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text('done', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w300)),
                            ],
                          )
                        // Paused: render the frozen timer's own static
                        // `remaining` directly, no _TimerTicker — that
                        // widget extrapolates forward from `asOf` using
                        // wall-clock time, which is exactly wrong here:
                        // the countdown must hold still, not keep ticking
                        // down as if still running.
                        //
                        // Regression: this used to switch on `_isPaused`
                        // alone. _handleResumeButtonTap clears _isPaused
                        // synchronously in the same tap that requests a
                        // real Resume from Clock — but widget.timer itself
                        // doesn't get a fresh, live asOf until the *next*
                        // real poll tick, up to ~1s later. In that gap,
                        // `_isPaused == false` took this into the
                        // _TimerTicker branch below, constructed with
                        // `timer` (== _lastRealTimer, a static snapshot
                        // whose `asOf` was deliberately omitted at pause
                        // time). currentRemaining()'s own short-circuit
                        // (`if (baseline == null) return remaining;`) then
                        // made every one of that ticker's 100ms ticks
                        // return the exact same frozen value for the
                        // entire gap — confirmed live via frame-by-frame
                        // logging: progressFraction held dead flat for
                        // ~770ms, then snapped straight to the real
                        // value the instant a genuinely live widget.timer
                        // (asOf set) finally arrived. That freeze-then-
                        // snap is exactly the reported "laggy" bar.
                        // Ticking is only actually safe once widget.timer
                        // itself is live again, not merely once the local
                        // _isPaused flag says so.
                        : widget.timer == null
                        ? _TimerProgress(remaining: timer.remaining, progressFraction: timer.progressFraction(), title: title, otherTimerCount: otherTimerCount)
                        : _TimerTicker(
                            timer: timer,
                            builder: (context, remaining, progressFraction) =>
                                _TimerProgress(remaining: remaining, progressFraction: progressFraction, title: title, otherTimerCount: otherTimerCount),
                          ),
                  ),
                ),
                // Neither button has a real, meaningful action to take
                // against a *ringing* timer — it's a fired alert, not a
                // live countdown in Clock's own Timers tab, so there's no
                // real "Pause" or "Cancel" target for
                // ClockTimerController's AX press to find. Confirmed live:
                // showing them anyway (an earlier version did) let a stray
                // "Pause" tap here freeze this widget permanently, with no
                // real timer left for "Resume" to ever un-freeze — the
                // exact stuck-forever bug this whole redesign exists to
                // avoid. Hiding them is a smaller, more honest fix than
                // inventing an unverified "actually dismiss the alert"
                // action to replace them with.
                if (!isRinging) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _StopwatchActionButton(label: 'Cancel', color: Colors.white24, onTap: _handleCancelButtonTap),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StopwatchActionButton(
                          label: _isPaused ? 'Resume' : 'Pause',
                          color: _isPaused ? _timerResumeAccent : _timerAccent,
                          onTap: _isPaused ? _handleResumeButtonTap : _handlePauseButtonTap,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            // An overlay, not a Column sibling — see
            // _StopwatchExpandedState's own equivalent for why: this
            // fixed-size card has no spare vertical budget anywhere, and a
            // Column slot (even a fixed-height one) borrows space from
            // this Column's own Expanded region, which doesn't have any
            // to give without something else overflowing.
            if (!isRinging && _showUnreachable)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // Purely informational — the buttons underneath must stay
                // tappable while this briefly shows (confirmed live: a
                // second tap on the same button right after a failure,
                // e.g. Resume twice in a row, hit-tested this banner's own
                // Text instead of the button beneath it, since Positioned
                // otherwise happily intercepts pointer events).
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Text(
                      "Can't Reach Clock Right Now... Switch to Desktop",
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Icon/name row, a big countdown, and a horizontal progress bar depleting
/// left-to-right as [progressFraction] falls from 1.0 (just started) to 0.0
/// (about to fire) — the filled portion represents time *remaining*, same
/// meaning [progressFraction] already carries from
/// ClockRunningTimer.progressFraction, just drawn as a bar instead of an
/// arc.
class _TimerProgress extends StatelessWidget {
  const _TimerProgress({required this.remaining, required this.progressFraction, required this.title, required this.otherTimerCount});

  final Duration remaining;
  final double progressFraction;
  final String title;
  final int otherTimerCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (otherTimerCount > 0) ...[
              const SizedBox(width: 6),
              Text('+$otherTimerCount', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          formatTimerDuration(remaining),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w300,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          // Eases to each new progressFraction rather than snapping —
          // purely cosmetic smoothing, requested to soften the visible
          // step whenever a value handoff (e.g. widget.timer's own
          // pause/resume transition) lands as a single larger jump
          // instead of the usual run of tiny per-tick steps.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: progressFraction, end: progressFraction),
            duration: const Duration(milliseconds: 250),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(_timerAccent),
            ),
          ),
        ),
      ],
    );
  }
}

/// Whether a lap row is Clock's fastest or slowest recorded split — decided
/// once, in [_StopwatchExpanded._buildLapRows], across *all* recorded laps
/// (not just whichever 3 are currently visible) and *excluding* the
/// in-progress row, matching Clock's own behavior exactly: confirmed live
/// against Clock's real Accessibility tree, whose own lap descriptions tag
/// only the not-yet-finalized row with a trailing "elapsed" — the same row
/// Clock always renders in plain white, never ranked.
enum _LapRank { none, fastest, slowest }

/// Lap number, split (time since the previous lap), and running total for
/// one lap — [rank] is decided once across the whole recorded history (see
/// [_LapRank]), not re-derived per-row or from whatever subset happens to be
/// on screen.
class _LapRow {
  const _LapRow({required this.number, required this.split, required this.total, this.rank = _LapRank.none});

  final int number;
  final Duration split;
  final Duration total;
  final _LapRank rank;
}

/// Shared by [_StopwatchExpanded] and [_TimerExpanded]: both drive Clock via
/// the same AX-scripting path, which has exactly one confirmed, real way to
/// fail — Clock's window sitting on a macOS Space that isn't currently
/// active (see ClockUIController.onMainWindow's own doc comment; some other
/// app full-screen, or just a different virtual desktop, is a documented
/// WindowServer/Accessibility limitation with no public-API workaround, not
/// a bug to keep chasing here). A silent no-op on that failure — which is
/// all this used to do, since ClockAwarenessControl's methods returned void
/// and nothing here ever inspected whether the command actually landed — is
/// exactly the confirmed-live report that motivated this: pressing Lap/Stop
/// while on a different desktop simply did nothing, with no indication why.
/// This surfaces that failure briefly instead, auto-clearing so it doesn't
/// become a second stale state to manage.
mixin _ClockCommandFeedback<T extends StatefulWidget> on State<T> {
  static const _visibleFor = Duration(seconds: 2);
  Timer? _feedbackTimer;
  bool _showUnreachable = false;

  void _reportResult(bool succeeded) {
    _feedbackTimer?.cancel();
    if (succeeded) {
      if (_showUnreachable) setState(() => _showUnreachable = false);
      return;
    }
    setState(() => _showUnreachable = true);
    _feedbackTimer = Timer(_visibleFor, () {
      if (mounted) setState(() => _showUnreachable = false);
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }
}

/// The Stopwatch expanded card — icon/label/time on the left (30%), Clock's
/// own lap table on the right (70%), a divider, then Lap/Stop buttons that
/// drive the real Clock app (see ClockAwarenessControl/
/// ClockStopwatchController.swift) as well as this card's own display.
class _StopwatchExpanded extends StatefulWidget {
  const _StopwatchExpanded({required this.stopwatch, required this.elapsed});

  final ClockRunningStopwatch stopwatch;
  final Duration elapsed;

  @override
  State<_StopwatchExpanded> createState() => _StopwatchExpandedState();
}

class _StopwatchExpandedState extends State<_StopwatchExpanded> with _ClockCommandFeedback<_StopwatchExpanded> {
  @override
  Widget build(BuildContext context) {
    final laps = _buildLapRows();
    return Semantics(
      label: 'Stopwatch, ${formatStopwatchDuration(widget.elapsed)} elapsed'
          '${laps.isEmpty ? '' : ', lap ${laps.last.number}, split ${formatStopwatchDuration(laps.last.split)}'}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 30, child: _StopwatchTimeColumn(elapsed: widget.elapsed)),
                      Expanded(flex: 70, child: _LapTable(laps: laps)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(color: Colors.white24, height: 1, thickness: 1),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _StopwatchActionButton(
                        label: 'Lap',
                        color: Colors.white24,
                        onTap: () => ClockAwarenessControl.lap().then(_reportResult),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StopwatchActionButton(
                        label: 'Stop',
                        color: const Color(0xFFFF6B35),
                        onTap: () => ClockAwarenessControl.stop().then(_reportResult),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // An overlay, not a Column sibling — this fixed-size card has
            // no spare vertical budget anywhere (confirmed live: giving
            // this message its own Column slot, even at a fixed height,
            // shrank the lap table's own share of the layout by that same
            // amount, and _LapTable's inner Column doesn't compress below
            // its own content height, so it overflowed instead). Sitting
            // on top of the button row for this message's brief ~2s
            // lifetime costs nothing else on screen.
            if (_showUnreachable)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // See _TimerExpandedState's own equivalent for why —
                // Positioned otherwise intercepts taps meant for the
                // Lap/Stop buttons underneath while this briefly shows.
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Text(
                      "Can't Reach Clock Right Now... Switch to Desktop",
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Clock's own lap table always shows (up to) the 3 most recent laps —
  /// matching the screenshot rather than trying to fit an arbitrarily long
  /// history into a fixed-height card. The in-progress span since the last
  /// recorded lap is shown as the latest/topmost row, live-ticking (its
  /// split and total both grow every frame, same as Clock's own top row
  /// does while running) — not held back until the next real lap is taken.
  ///
  /// Fastest/slowest is ranked across *every* recorded lap, not just the (up
  /// to) 3 being shown, and the in-progress row is excluded from ranking
  /// entirely — both confirmed against Clock's own behavior live (see
  /// [_LapRank]'s doc comment). Getting this wrong once looked plausible:
  /// ranking only the visible slice colored whichever 3 laps happened to be
  /// on screen as if they were the true fastest/slowest, and including the
  /// in-progress row let its own still-growing split occasionally win
  /// "slowest" by default, coloring a row Clock itself never ranks at all.
  /// (An even-later attempt changed *which* 3 rows are shown at all —
  /// always the in-progress lap plus the true fastest/slowest, not simply
  /// the 3 most recent — but that wasn't wanted; reverted back to plain
  /// recency for *selection*, while keeping full-history ranking for
  /// *coloring* whichever 3 recent rows end up shown.)
  List<_LapRow> _buildLapRows() {
    final recorded = widget.stopwatch.laps;
    final priorTotal = recorded.fold<Duration>(Duration.zero, (sum, lap) => sum + lap);
    final currentSpan = widget.elapsed - priorTotal;

    Duration? fastest;
    Duration? slowest;
    if (recorded.length > 1) {
      for (final split in recorded) {
        if (fastest == null || split < fastest) fastest = split;
        if (slowest == null || split > slowest) slowest = split;
      }
      if (fastest == slowest) {
        fastest = null;
        slowest = null;
      }
    }
    _LapRank rankFor(Duration split) {
      if (fastest != null && split == fastest) return _LapRank.fastest;
      if (slowest != null && split == slowest) return _LapRank.slowest;
      return _LapRank.none;
    }

    final rows = <_LapRow>[
      for (var i = 0; i < recorded.length; i++)
        _LapRow(
          number: i + 1,
          split: recorded[i],
          total: recorded.take(i + 1).fold<Duration>(Duration.zero, (sum, lap) => sum + lap),
          rank: rankFor(recorded[i]),
        ),
      _LapRow(number: recorded.length + 1, split: currentSpan.isNegative ? Duration.zero : currentSpan, total: widget.elapsed),
    ];
    return rows.length > 3 ? rows.sublist(rows.length - 3) : rows;
  }
}

class _StopwatchTimeColumn extends StatelessWidget {
  const _StopwatchTimeColumn({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer, color: Colors.white, size: 18),
        const SizedBox(height: 3),
        const Text(
          'Stopwatch',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatStopwatchDuration(elapsed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Clock's own lap table shape: newest lap on top, the fastest split in
/// green, the slowest in red. Purely a renderer — [_LapRow.rank] is already
/// decided (see [_StopwatchExpanded._buildLapRows]) across the full lap
/// history before trimming to whichever (up to) 3 rows are visible here, so
/// this never re-derives ranking from the trimmed subset it's actually
/// given.
class _LapTable extends StatelessWidget {
  const _LapTable({required this.laps});

  final List<_LapRow> laps;

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) return const SizedBox.shrink();
    final newestFirst = laps.reversed.toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, right: 4, bottom: 2),
          child: _LapRowLayout(
            lapNo: Text('Lap', maxLines: 1, softWrap: false, style: TextStyle(color: Colors.white38, fontSize: 9)),
            split: Text(
              'Split',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white38, fontSize: 9),
            ),
            total: Text(
              'Total',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ),
        ),
        for (final row in newestFirst)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4, top: 1, bottom: 1),
            child: _LapRowLayout(
              lapNo: Text(
                '${row.number}',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: _rowColor(row.rank), fontSize: 11),
              ),
              split: Text(
                formatStopwatchDuration(row.split),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.right,
                style: TextStyle(color: _rowColor(row.rank), fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              total: Text(
                formatStopwatchDuration(row.total),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.right,
                style: TextStyle(color: _rowColor(row.rank), fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
      ],
    );
  }

  Color _rowColor(_LapRank rank) {
    return switch (rank) {
      _LapRank.fastest => const Color(0xFF32D74B),
      _LapRank.slowest => const Color(0xFFFF453A),
      _LapRank.none => Colors.white,
    };
  }
}

/// One lap row's 3 columns at fixed proportions — shared by the header and
/// every data row so their columns always line up.
class _LapRowLayout extends StatelessWidget {
  const _LapRowLayout({required this.lapNo, required this.split, required this.total});

  final Widget lapNo;
  final Widget split;
  final Widget total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 22, child: lapNo),
        Expanded(flex: 39, child: split),
        Expanded(flex: 39, child: total),
      ],
    );
  }
}

class _StopwatchActionButton extends StatelessWidget {
  const _StopwatchActionButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      // AnimatedContainer (not a plain Material(color:)) specifically so a
      // color change — Pause↔Resume's orange↔green swap — eases smoothly
      // rather than snapping instantly; Material itself only picks up the
      // color at whatever value it's built with each frame, it doesn't
      // animate between two colors on its own. Every other caller of this
      // button (Cancel, Lap, Stop) never actually changes its own color at
      // runtime, so this costs them nothing beyond an unused capability.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Center(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
