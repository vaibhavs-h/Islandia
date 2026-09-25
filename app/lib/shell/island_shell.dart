import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/activity.dart';
import '../engine/activity_stack.dart';
import '../providers/audio_route_provider.dart';
import '../providers/battery_activity.dart';
import '../providers/battery_provider.dart';
import '../providers/bluetooth_battery_activity.dart';
import '../providers/bluetooth_battery_provider.dart';
import '../providers/bluetooth_classic_provider.dart';
import '../providers/calamity_alert_activity.dart';
import '../providers/calamity_alert_provider.dart';
import '../providers/camera_activity_activity.dart';
import '../providers/camera_activity_provider.dart';
import '../providers/clock_alarm_activity.dart';
import '../providers/clock_awareness_activity.dart';
import '../providers/clock_awareness_provider.dart';
import '../providers/microphone_activity_activity.dart';
import '../providers/microphone_activity_provider.dart';
import '../providers/now_playing_activity.dart';
import '../providers/now_playing_provider.dart';
import '../providers/now_playing_visibility_gate.dart';
import '../providers/screen_capture_activity.dart';
import '../providers/screen_capture_activity_provider.dart';
import '../providers/weather_activity.dart';
import '../providers/weather_provider.dart';
import '../providers/wifi_connection_activity.dart';
import '../providers/wifi_connection_provider.dart';
import 'island_window_channel.dart';
import 'motion.dart';
import 'pill_geometry.dart';
import 'privacy_indicator.dart';

/// Which of {Stopwatch, Timer, Now Playing} — if any — currently holds the
/// shared `clock` tier slot. See [resolveClockTierWinner] for the decision
/// and _IslandShellState._refreshClockTierActivity for how a winner turns
/// into an actual stack registration.
enum ClockTierWinner { stopwatch, timer, nowPlaying, none }

/// Pure decision function for [ClockTierWinner] — kept free of widgets and
/// state (just like clock_awareness_activity.dart's own
/// selectClockAwarenessView) so the exact user-confirmed algorithm is
/// unit-testable without pumping a widget tree.
///
/// The algorithm, verbatim from what was confirmed:
/// - Stopwatch running: Stopwatch wins, UNLESS a timer is running with
///   ≤10s left ([timerPreemptWindow] in clock_awareness_activity.dart) —
///   Now Playing is irrelevant in this entire branch, confirmed explicitly.
/// - Stopwatch not running: a timer with ≤1 minute left
///   ([timerVsNowPlayingPreemptWindow]) wins; else Now Playing wins if
///   visible; else an idle running timer still wins by default (nothing
///   else contesting); else no winner (Dashboard shows through).
ClockTierWinner resolveClockTierWinner({
  required bool hasStopwatch,
  required Duration? timerRemaining,
  required bool nowPlayingVisible,
}) {
  final hasTimer = timerRemaining != null;

  if (hasStopwatch) {
    final timerInPreemptWindow = hasTimer && timerRemaining <= timerPreemptWindow;
    return timerInPreemptWindow ? ClockTierWinner.timer : ClockTierWinner.stopwatch;
  }

  if (hasTimer && timerRemaining <= timerVsNowPlayingPreemptWindow) return ClockTierWinner.timer;
  if (nowPlayingVisible) return ClockTierWinner.nowPlaying;
  if (hasTimer) return ClockTierWinner.timer;
  return ClockTierWinner.none;
}

/// The Island itself: one collapsed↔hover↔expanded↔interactive↔collapse
/// state machine (§00), rendering whatever the Activity Stack's top entry
/// currently is. This is the Phase 1 spike target — proving the shell and
/// engine work end-to-end on fake activities before any real provider exists.
class IslandShell extends StatefulWidget {
  const IslandShell({super.key});

  @override
  State<IslandShell> createState() => _IslandShellState();
}

class _IslandShellState extends State<IslandShell> with TickerProviderStateMixin {
  static const Size _collapsedSize = Size(253, 41);
  // Now Playing's dense case (title + artist + audio route + controls, all
  // tightened as far as they comfortably go) needs 134 of this — a few px
  // of margin, not shaved down to exactly that, since real content varies
  // slightly from the one snapshot this was measured against.
  static const Size _expandedSize = Size(360, 136);

  static const Duration _autoCollapseDelay = Duration(seconds: 5);

  final ActivityStack _stack = ActivityStack();
  final FocusNode _focusNode = FocusNode(debugLabel: 'IslandShell');
  late final NowPlayingVisibilityGate _nowPlayingVisibility = NowPlayingVisibilityGate(
    hideAfterPaused: const Duration(seconds: 15),
    onHide: _refreshClockTierActivity,
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

  /// 0 when nothing but the battery fallback is showing (the dots' normal,
  /// vertically-centered home), 1 whenever anything else — Now Playing, a
  /// Bluetooth alert, even one of the privacy activities' own prominent
  /// banners — has taken the top slot instead, which is exactly when a
  /// centered dot would sit on top of that content's own elements. See
  /// _privacyDots().
  late final AnimationController _dotsCompactTransition = AnimationController(
    vsync: this,
    // Deliberately slower than the content cross-fade — explicitly asked
    // for as a slow, smooth shift, not something snappy enough to draw the
    // eye on its own.
    duration: const Duration(milliseconds: 500),
  );

  // Mic and camera both use the shared prominent-then-dot behavior (see
  // PrivacyIndicatorController) — each owns its own animation clock and
  // Activity Stack lifecycle, positioned side by side in build() below so
  // both dots can be visible at once without overlapping.
  late final PrivacyIndicatorController _microphoneIndicator = PrivacyIndicatorController(
    activityId: 'microphone-activity',
    buildActivity: buildMicrophoneActivity,
    stack: _stack,
    vsync: this,
  );
  late final PrivacyIndicatorController _cameraIndicator = PrivacyIndicatorController(
    activityId: 'camera-activity',
    buildActivity: buildCameraActivity,
    stack: _stack,
    vsync: this,
  );
  late final PrivacyIndicatorController _screenCaptureIndicator = PrivacyIndicatorController(
    activityId: 'screen-capture-activity',
    buildActivity: buildScreenCaptureActivity,
    stack: _stack,
    vsync: this,
  );

  NotchGeometry? _screen;
  LifecycleState _state = LifecycleState.collapsed;
  Timer? _autoCollapseTimer;
  bool _isHovering = false;
  StreamSubscription<BatterySnapshot>? _batterySubscription;
  StreamSubscription<NowPlayingSnapshot?>? _nowPlayingSubscription;
  StreamSubscription<AudioRouteSnapshot?>? _audioRouteSubscription;
  StreamSubscription<List<BluetoothDeviceBattery>>? _bluetoothBatterySubscription;
  /// Null until the first emission — that first one is the baseline of
  /// whatever's already connected when Islandia starts, not a batch of
  /// devices that all "just connected." Only emissions after that are
  /// diffed into connect/disconnect notifications.
  Set<String>? _lastBluetoothDeviceNames;
  StreamSubscription<BluetoothClassicEvent>? _bluetoothClassicSubscription;
  StreamSubscription<bool>? _microphoneActivitySubscription;
  StreamSubscription<bool>? _cameraActivitySubscription;
  StreamSubscription<bool>? _screenCaptureActivitySubscription;
  StreamSubscription<ClockAwarenessSnapshot>? _clockAwarenessSubscription;
  /// Null until the first snapshot arrives — needed alongside
  /// [_lastClockAwarenessView] because the Now-Playing-triggered half of
  /// _refreshClockTierActivity has to re-run the Stopwatch/Timer/Now-Playing
  /// decision without a fresh ClockAwarenessSnapshot of its own to hand in
  /// (Now Playing updates arrive on a completely separate stream — see
  /// _refreshClockTierActivity's own doc comment).
  ClockAwarenessSnapshot? _lastClockAwarenessSnapshot;
  /// Null until the first snapshot decides it — see
  /// _refreshClockTierActivity for why this (not just the id string
  /// alone) is what decides whether a fresh registration counts as a real
  /// view change.
  ClockAwarenessView? _lastClockAwarenessView;
  int _clockAwarenessViewGeneration = 0;
  /// Null until the first snapshot arrives — same guard shape as
  /// [_lastBluetoothDeviceNames]: the very first snapshot is Clock's own
  /// already-existing alarms, not a batch that all "just got created."
  /// Keyed on the full alarm, not just its id, so a deleted alarm's own
  /// title/time can still be reported (its own snapshot no longer has
  /// them; the previous one does).
  Map<String, ClockAlarm>? _lastAlarmsById;

  /// Set the instant the island's own Pause button is tapped (see
  /// buildClockAwarenessActivity's onTimerPauseRequested), cleared on
  /// Resume, on Cancel, and unconditionally in _collapse() — i.e., it
  /// lives exactly as long as "the user paused a timer via this button and
  /// hasn't collapsed the view since." This is deliberately *not* a data
  /// override — an earlier version remembered the paused timer's own
  /// frozen state and spliced it back into every snapshot, which
  /// (confirmed live, three separate real bugs from one test sequence)
  /// could fight the app's own real stopwatch/timer priority rules and,
  /// worst of all, had no path to ever clear itself while the view stayed
  /// continuously expanded — it got permanently stuck, immune even to a
  /// real Cancel from Clock itself, surviving until a full app restart.
  ///
  /// A second version tried a short, fixed 2-second expiry instead of
  /// tying this to the expand/collapse lifecycle — also wrong, confirmed
  /// live by screen recording: explicitly requested behavior is that
  /// pausing a timer holds *that timer's own view* on screen for as long
  /// as the expanded card stays open, not merely for a couple of seconds
  /// before a stopwatch is allowed to reclaim the slot on its own real
  /// merits. _refreshClockTierActivity uses this flag to override *what
  /// view shows* while it's true (see its own doc comment) — not just
  /// whether the widget's own last frame survives, which is
  /// _TimerExpanded's own separate, local concern (see its doc comment).
  bool _timerHeldByPause = false;
  StreamSubscription<WiFiConnectionEvent>? _wifiConnectionSubscription;
  StreamSubscription<WeatherSnapshot>? _weatherSubscription;
  StreamSubscription<CalamityAlert>? _calamityAlertSubscription;

  /// USGS/GDACS keep an event in their own feed for a while (e.g. an
  /// earthquake stays in USGS's "past day" feed for 24h), so native
  /// re-emits the same event id on every poll tick it's still present —
  /// without this, the same earthquake would re-alert every 1-5 minutes
  /// for as long as it stays in the feed. Alert once per genuinely new id,
  /// same reasoning as _lastAlarmsById's own diffing, just a simpler Set
  /// since there's no "edited" or "removed" case here to track, only
  /// "have I already shown this."
  final Set<String> _seenCalamityAlertIds = {};

  /// Tracks only the severe/not-severe edge — the P2 alert should fire once
  /// on the transition into severe conditions, not every hourly poll tick
  /// for as long as it stays severe (which would just be the same
  /// notification repeating with nothing new to say). Null until the first
  /// reading arrives, so that first reading is captured as a baseline
  /// rather than treated as a transition even if it happens to already be
  /// severe — same "don't announce what was already true" rule
  /// WiFiConnectionChannel's lastKnownSSID follows.
  bool? _lastWeatherWasSevere;
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

  /// AnimatedSwitcher keys its transitioning children on the top activity's
  /// id (see _crossFadedContent) — but a `Timer`-driven activity that
  /// appears and disappears fast enough (a screenshot's screen-capture blip
  /// added/removed ~20ms apart, say) can make the *same* id reappear while
  /// the previous instance of that same id is still mid-exit from an earlier
  /// transition. AnimatedSwitcher ends up with two entries carrying the same
  /// key — "Duplicate keys found" — since it doesn't expect a key it's
  /// currently animating out to be handed back to it as a new child. Tagging
  /// each genuine identity change with an incrementing generation makes
  /// every entry's key unique regardless of how fast the same id cycles
  /// through, so there's never a collision to crash on.
  String? _lastTopId;
  int _topIdGeneration = 0;

  /// Starts true to match _dotsCompactTransition's own starting value (0,
  /// i.e. "home") — the battery fallback really is what's showing before
  /// anything else has ever registered, so there's nothing to animate on
  /// the very first build.
  bool _lastIsHomeState = true;

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
    _dotsCompactTransition.dispose();
    _microphoneIndicator.dispose();
    _cameraIndicator.dispose();
    _screenCaptureIndicator.dispose();
    _autoCollapseTimer?.cancel();
    _nowPlayingVisibility.dispose();
    _batterySubscription?.cancel();
    _nowPlayingSubscription?.cancel();
    _audioRouteSubscription?.cancel();
    _bluetoothBatterySubscription?.cancel();
    _bluetoothClassicSubscription?.cancel();
    _microphoneActivitySubscription?.cancel();
    _cameraActivitySubscription?.cancel();
    _screenCaptureActivitySubscription?.cancel();
    _clockAwarenessSubscription?.cancel();
    _wifiConnectionSubscription?.cancel();
    _weatherSubscription?.cancel();
    _calamityAlertSubscription?.cancel();
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
      _refreshClockTierActivity();
    });
    // A second, independent provider (CoreAudio) — only relevant to
    // re-render Now Playing's "via AirPods Pro" line, never gates whether
    // Now Playing itself is registered.
    _audioRouteSubscription = AudioRouteProvider.updates.listen((route) {
      _lastAudioRoute = route;
      _refreshClockTierActivity();
    });

    _batterySubscription = BatteryProvider.updates.listen(
      (snapshot) => _stack.register(buildBatteryActivity(snapshot)),
    );

    // Only the standard GATT Battery Service — an empty list (nothing
    // connected reports battery this way) is real and common, not an error;
    // same null/empty-means-absent gating as Now Playing above.
    _bluetoothBatterySubscription = BluetoothBatteryProvider.updates.listen((devices) {
      if (devices.isEmpty) {
        _stack.remove('bluetooth-battery');
      } else {
        _stack.register(buildBluetoothBatteryActivity(devices));
      }
      _detectBluetoothConnectionChanges(devices);
    });

    // Classic accessories (headphones, earbuds, speakers) never appear in
    // the CoreBluetooth-based stream above at all — see
    // BluetoothClassicChannel.swift for why. IOBluetooth hands over discrete
    // connect/disconnect events directly, so unlike the snapshot-diffing
    // above, this just forwards each one straight to the same notification
    // slot. Battery (see the provider and the native side for where it
    // actually comes from) rides along on the same event when a connect
    // happened to have one available.
    _bluetoothClassicSubscription = BluetoothClassicProvider.updates.listen((event) {
      _stack.register(
        buildBluetoothConnectionActivity(
          deviceName: event.name,
          connected: event.connected,
          batteryPercent: event.batteryPercent,
        ),
      );
    });

    _microphoneActivitySubscription = MicrophoneActivityProvider.updates.listen(_microphoneIndicator.handle);
    _cameraActivitySubscription = CameraActivityProvider.updates.listen(_cameraIndicator.handle);
    _screenCaptureActivitySubscription = ScreenCaptureActivityProvider.updates.listen(_screenCaptureIndicator.handle);

    _clockAwarenessSubscription = ClockAwarenessProvider.updates.listen((snapshot) {
      _lastClockAwarenessSnapshot = snapshot;
      _refreshRingingTimerActivity(snapshot);
      _detectAlarmChanges(snapshot.alarms);
      _refreshClockTierActivity();
    });

    // Same discrete-event shape as BluetoothClassicProvider above — native
    // already hands over distinct join/leave events, nothing to diff here.
    _wifiConnectionSubscription = WiFiConnectionProvider.updates.listen((event) {
      _stack.register(buildWiFiConnectionActivity(networkName: event.name, connected: event.connected));
    });

    _weatherSubscription = WeatherProvider.updates.listen((snapshot) {
      _stack.register(buildWeatherActivity(snapshot));
      final wasSevere = _lastWeatherWasSevere;
      _lastWeatherWasSevere = snapshot.isSevere;
      // Only the transition into severe fires the P2 alert — see
      // _lastWeatherWasSevere's own doc comment.
      if (snapshot.isSevere && wasSevere == false) {
        _stack.register(buildSevereWeatherAlertActivity(snapshot));
      }
    });

    _calamityAlertSubscription = CalamityAlertProvider.updates.listen((alert) {
      if (_seenCalamityAlertIds.add(alert.id)) {
        _stack.register(buildCalamityAlertActivity(alert));
      }
    });

    if (!mounted) return;
    setState(() => _screen = screen);
    await _applyFrame(animated: false);
  }

  /// Diffs successive battery-list snapshots into connect/disconnect
  /// notifications — no separate native channel needed, since a device
  /// joining or leaving the tracked set is exactly what a name appearing or
  /// disappearing from this list means. If both happen in the same tick,
  /// the disconnect wins the (single, shared) notification slot — arbitrary,
  /// but a real simultaneous connect+disconnect is not a case worth
  /// engineering around.
  void _detectBluetoothConnectionChanges(List<BluetoothDeviceBattery> devices) {
    final currentNames = devices.map((d) => d.name).toSet();
    final previousNames = _lastBluetoothDeviceNames;
    _lastBluetoothDeviceNames = currentNames;
    if (previousNames == null) return;

    final disconnected = previousNames.difference(currentNames);
    if (disconnected.isNotEmpty) {
      _stack.register(buildBluetoothConnectionActivity(deviceName: disconnected.first, connected: false));
      return;
    }
    final connected = currentNames.difference(previousNames);
    if (connected.isNotEmpty) {
      final name = connected.first;
      // The device that just connected is in this same snapshot — its
      // current reading, not a lookup anywhere else.
      final percent = devices.where((d) => d.name == name).firstOrNull?.batteryPercent;
      _stack.register(buildBluetoothConnectionActivity(deviceName: name, connected: true, batteryPercent: percent));
    }
  }

  /// Diffs successive alarm-list snapshots into created/deleted/edited/
  /// enabled/disabled alerts — same shape as
  /// [_detectBluetoothConnectionChanges] above, for the same reason:
  /// there's no native push for "an alarm was just created," only polled
  /// snapshots of what currently exists (see
  /// ClockPreferencesReader.alarms()'s own doc comment). An edit or a
  /// toggle is its own case, not folded into created/deleted — confirmed
  /// live that changing an existing alarm's time (or flipping its
  /// enabled switch) keeps its own id unchanged, so either is invisible
  /// to a plain id-set difference; only comparing the two alarms *with
  /// the same id* field-by-field can catch either. The time-edit check is
  /// scoped to hour/minute specifically (explicitly requested as "just
  /// for time changes") — a title edit deliberately doesn't trigger it.
  ///
  /// The enabled/disabled check has one deliberate exclusion: a one-off
  /// (non-repeating) alarm auto-disables itself the instant it actually
  /// fires — confirmed live, MTAlarmEnabled flips straight from 1 to 0
  /// right as it rings — which would otherwise look identical to the
  /// user flipping the switch off themselves. [_looksLikeAutoDisable]
  /// filters that out by checking whether the disable landed within a
  /// minute of the alarm's own scheduled hour:minute — a real user
  /// toggle essentially never coincides with that exact window, so this
  /// is a safe (if not airtight) heuristic, not a guarantee.
  ///
  /// If more than one kind of change lands in the same poll tick, the
  /// single shared alert slot picks one in this priority order —
  /// deletion, then edit, then enabled/disabled, then creation — same
  /// arbitrary-but-acceptable tiebreak shape Bluetooth's own version
  /// already makes for a simultaneous connect+disconnect.
  void _detectAlarmChanges(List<ClockAlarm> alarms) {
    final currentById = {for (final alarm in alarms) alarm.id: alarm};
    final previousById = _lastAlarmsById;
    _lastAlarmsById = currentById;
    if (previousById == null) return;

    final deletedIds = previousById.keys.toSet().difference(currentById.keys.toSet());
    if (deletedIds.isNotEmpty) {
      _stack.register(buildAlarmAlertActivity(alarm: previousById[deletedIds.first]!, kind: AlarmChangeKind.deleted));
      return;
    }

    final sharedIds = currentById.keys.toSet().intersection(previousById.keys.toSet());
    for (final id in sharedIds) {
      final before = previousById[id]!;
      final after = currentById[id]!;
      if (before.hour != after.hour || before.minute != after.minute) {
        _stack.register(buildAlarmAlertActivity(alarm: after, kind: AlarmChangeKind.edited));
        return;
      }
    }
    for (final id in sharedIds) {
      final before = previousById[id]!;
      final after = currentById[id]!;
      if (before.enabled == after.enabled) continue;
      if (!after.enabled && _looksLikeAutoDisable(after)) continue;
      _stack.register(buildAlarmAlertActivity(alarm: after, kind: after.enabled ? AlarmChangeKind.enabled : AlarmChangeKind.disabled));
      return;
    }

    final createdIds = currentById.keys.toSet().difference(previousById.keys.toSet());
    if (createdIds.isNotEmpty) {
      _stack.register(buildAlarmAlertActivity(alarm: currentById[createdIds.first]!, kind: AlarmChangeKind.created));
    }
  }

  /// Within a minute either side of the alarm's own scheduled time — see
  /// [_detectAlarmChanges]'s own doc comment for why this specific window
  /// (not "just disabled" alone) is what distinguishes Clock's own
  /// post-fire auto-disable from the user actually flipping the switch.
  static bool _looksLikeAutoDisable(ClockAlarm alarm) {
    final now = DateTime.now();
    final scheduledToday = DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
    return now.difference(scheduledToday).abs() <= const Duration(minutes: 1);
  }

  /// A plain register/remove, not diffed against a remembered previous value
  /// the way _detectAlarmChanges is — buildAlarmRingingActivity and
  /// buildTimerRingingActivity both return the exact same fixed-id Activity
  /// every call, so registering one again on every snapshot while still
  /// ringing is an idempotent update (ActivityStack.register replaces in
  /// place on a matching id), not a repeated arrival the way a fresh
  /// alarm-alert id would be.
  ///
  /// Split out from the old _refreshClockAwarenessActivity specifically so
  /// a ringing timer registers at `ringingEvent` tier (see
  /// buildTimerRingingActivity's own doc comment for why) instead of being
  /// just another candidate in [_refreshClockTierActivity]'s
  /// Stopwatch/Timer/Now-Playing contest at the ordinary `clock` tier — a
  /// ringing timer should preempt an Alert or Now Playing outright, not win
  /// a popularity contest against them.
  void _refreshRingingTimerActivity(ClockAwarenessSnapshot snapshot) {
    if (snapshot.isAlarmRinging) {
      _stack.register(buildTimerRingingActivity(snapshot));
    } else {
      _stack.remove('timer-ringing');
    }
  }

  /// Decides which ONE of {Stopwatch, Timer, Now Playing} — if any — holds
  /// the shared `clock` tier slot right now, per the exact algorithm
  /// confirmed with the user:
  ///
  /// - A **running stopwatch** wins outright UNLESS a running timer has
  ///   ≤10s left ([timerPreemptWindow] in clock_awareness_activity.dart),
  ///   in which case the timer preempts it. Now Playing is irrelevant in
  ///   this branch even if it's actively playing — confirmed explicitly:
  ///   "Now Playing is irrelevant whenever stopwatch is running."
  /// - With **no stopwatch running**: a running timer with ≤1 minute left
  ///   ([timerVsNowPlayingPreemptWindow]) wins outright; otherwise Now
  ///   Playing wins if it's currently visible (see
  ///   [NowPlayingVisibilityGate] — playing, or paused within its own
  ///   hide-after grace period); otherwise an idle (>1min) running timer
  ///   still wins by default, since nothing else is contesting the slot;
  ///   otherwise nothing registers here at all and Dashboard shows through.
  ///
  /// A genuinely *ringing* timer never reaches this function — see
  /// [_refreshRingingTimerActivity] above, called separately at
  /// `ringingEvent` tier before this one ever runs.
  ///
  /// Called from three independent listeners (Now Playing's own snapshot
  /// stream, the CoreAudio route stream, and the Clock-awareness stream) —
  /// any one of the three inputs changing can flip who wins the slot, so
  /// all three re-run the full decision rather than each patching their own
  /// corner of it.
  void _refreshClockTierActivity() {
    final nowPlaying = _lastNowPlaying;
    _nowPlayingVisibility.update(isPlaying: nowPlaying?.isPlaying ?? false);
    final nowPlayingVisible = nowPlaying != null && !_nowPlayingVisibility.isHidden;

    final snapshot = _lastClockAwarenessSnapshot;
    final hasStopwatch = snapshot?.stopwatch != null;
    final soonest = snapshot?.soonest;

    // A timer held by pause overrides the *view itself* — not just its
    // widget's own rendering — against whatever the algorithm below would
    // otherwise decide, including a real, different view winning on its
    // own merits (a stopwatch legitimately becoming preferred once the
    // paused timer drops out of its preempt window). Confirmed live twice
    // (screen recordings caught both): an earlier version only intercepted
    // the case where there was *nothing* else left to show at all — a
    // stopwatch still running alongside the paused timer sailed right past
    // that check, since "show the stopwatch instead" is a real, non-null
    // decision, not the null-transition case that check was actually
    // guarding. A second version fixed that but used a short fixed expiry
    // instead of tying the hold to the expand/collapse lifecycle — also
    // confirmed wrong: explicitly requested behavior is that pausing a
    // timer holds its own view for as long as the expanded card stays
    // open, full stop, not merely for a couple of seconds before a
    // stopwatch (or Now Playing) can reclaim the slot.
    final winner = _timerHeldByPause && soonest != null
        ? ClockTierWinner.timer
        : resolveClockTierWinner(
            hasStopwatch: hasStopwatch,
            timerRemaining: soonest?.remaining,
            nowPlayingVisible: nowPlayingVisible,
          );

    switch (winner) {
      case ClockTierWinner.stopwatch:
      case ClockTierWinner.timer:
        final view = winner == ClockTierWinner.timer ? ClockAwarenessView.timer : ClockAwarenessView.stopwatch;
        if (view != _lastClockAwarenessView) {
          _clockAwarenessViewGeneration++;
        }
        _lastClockAwarenessView = view;
        _stack.remove('now-playing');
        _stack.register(
          buildClockAwarenessActivity(
            snapshot!,
            view,
            generation: _clockAwarenessViewGeneration,
            onTimerPauseRequested: _onTimerPauseRequested,
            onTimerCancelRequested: _onTimerHoldReleased,
            onTimerResumeRequested: _onTimerHoldReleased,
          ),
        );
      case ClockTierWinner.nowPlaying:
        _lastClockAwarenessView = null;
        _stack.remove('clock-awareness-$_clockAwarenessViewGeneration');
        _stack.register(buildNowPlayingActivity(
          nowPlaying!,
          audioRoute: _lastAudioRoute,
          onControlPressed: _startAutoCollapseTimer,
        ));
      case ClockTierWinner.none:
        _lastClockAwarenessView = null;
        _stack.remove('clock-awareness-$_clockAwarenessViewGeneration');
        _stack.remove('now-playing');
    }
  }

  /// Called the instant the island's own Pause button is tapped — see
  /// _timerHeldByPause's own doc comment for what this flag actually means
  /// and the two earlier, buggier designs it replaced.
  void _onTimerPauseRequested() {
    _timerHeldByPause = true;
  }

  /// Called the instant either Cancel or Resume is tapped while a timer is
  /// held by an earlier pause — both end the hold the same way: a canceled
  /// or resumed timer should compete for its view slot on its own real
  /// merits again (or, for cancel, have no slot to compete for at all),
  /// not stay artificially pinned by a pause that's no longer in effect.
  /// Without this, canceling or resuming a held timer would keep forcing
  /// the timer view to stay selected for as long as the expanded view
  /// happened to remain open — not the old permanent-forever bug, but
  /// still wrong.
  void _onTimerHoldReleased() {
    _timerHeldByPause = false;
  }

  void _onStackChanged() => setState(() {});

  void _handleScreenChange(NotchGeometry screen) {
    setState(() => _screen = screen);
    // A display swap isn't a UI-state transition — snap straight to the
    // correct spot rather than playing the expand/collapse motion for it.
    _applyFrame(animated: false);
  }

  // While collapsed, hover is cosmetic only — a mouse-over affordance, not
  // a trigger; expansion happens on click (see _handleTap). While expanded,
  // hover instead holds off the auto-collapse timer entirely (see
  // _startAutoCollapseTimer) for as long as the pointer stays over the
  // pill, so reading a longer countdown or scanning several lap rows never
  // gets cut off mid-read; leaving resumes the normal 5s countdown fresh,
  // same as any other "still relevant" interaction already does.
  void _handleHoverEnter() {
    _isHovering = true;
    if (_state == LifecycleState.collapsed) {
      setState(() => _state = LifecycleState.hover);
    }
  }

  void _handleHoverExit() {
    _isHovering = false;
    if (_state == LifecycleState.hover) {
      setState(() => _state = LifecycleState.collapsed);
    } else if (_state == LifecycleState.expanded) {
      _startAutoCollapseTimer();
    }
  }

  void _handleTap() {
    // A ringing alarm/timer already owns the surface until the real
    // external event resolves — see clock_alarm_activity.dart's own doc
    // comment.
    if (_stack.top?.priority == ActivityPriority.ringingEvent) return;
    if (_state == LifecycleState.collapsed || _state == LifecycleState.hover) {
      _expand();
    }
  }

  /// The shared expand sequence — factored out of _handleTap so it can be
  /// triggered from more than one gesture without duplicating it.
  void _expand() {
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

  void _handleOutsideClick() {
    if (_state == LifecycleState.expanded) {
      _collapse();
    }
  }

  /// A press that's relevant to whatever activity is currently showing
  /// (a playback control, cancelling a timer, a media key) — resets the
  /// auto-collapse clock, same as freshly expanding does. An irrelevant key
  /// (any regular letter) or a media key press while collapsed does not.
  ///
  /// If the pointer is still over the pill when this fires, collapsing is
  /// deferred rather than skipped outright — _handleHoverExit is what
  /// actually restarts a fresh countdown once the pointer leaves, but a
  /// short re-check here (rather than relying solely on that) means a
  /// timer already in flight when hovering begins still resolves itself
  /// correctly with nothing else needing to reschedule it in the meantime.
  void _startAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(_autoCollapseDelay, () {
      if (_state != LifecycleState.expanded) return;
      if (_isHovering) {
        _startAutoCollapseTimer();
        return;
      }
      _collapse();
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
    // A timer held by pause only holds its view for as long as the
    // expanded card stays open (see _timerHeldByPause's own doc comment,
    // and buildClockAwarenessActivity's) — collapsing, for any reason, is
    // the one thing that unconditionally ends the hold, letting whatever's
    // actually true (a stopwatch, a different timer, nothing) show once
    // this expands again.
    _timerHeldByPause = false;
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

  /// A generic (not Now-Playing-specific) cross-fade for every activity, on
  /// two independent axes:
  ///  - collapsed↔expanded of the *same* activity, driven by [t]
  ///    (unchanged from before — elements exclusive to one side ease in/out
  ///    instead of expandedBuilder's full layout rendering at full opacity
  ///    the instant you tap, with only the growing clip mask gradually
  ///    *uncovering* already-finished content).
  ///  - one activity replacing another *while staying in the same state*
  ///    (Now Playing stopping and battery resuming its place, both
  ///    collapsed) — previously an instant swap, since nothing was watching
  ///    for the top activity's *identity* changing, only its lifecycle
  ///    state. AnimatedSwitcher, keyed on [top.id], fades that too.
  /// Not a true shared-element morph (the artwork doesn't slide/grow from
  /// its collapsed position to its expanded one, and swapping activities
  /// doesn't slide old content out while new content slides in — both would
  /// need every activity's content rewritten as one Stack with lerped
  /// Positioned geometry, a bigger follow-up), but it replaces every
  /// "sudden appearance" in the shell with an actual transition.
  Widget _crossFadedContent(BuildContext context, Activity top, double t, Size contentSize) {
    final showCollapsed = t < 1.0;
    final showExpanded = t > 0.0;
    // See _topIdGeneration's doc comment — this, not top.id alone, is what
    // AnimatedSwitcher below keys its children on.
    final entryKey = ValueKey('${top.id}#$_topIdGeneration');
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        if (showCollapsed)
          Opacity(
            opacity: 1.0 - t,
            child: AnimatedSwitcher(
              duration: IslandMotion.activitySwapDuration,
              transitionBuilder: _sequentialFadeTransitionBuilder,
              child: KeyedSubtree(
                key: entryKey,
                child: _sizedOverlay(top.collapsedBuilder(context, _state), _collapsedSize),
              ),
            ),
          ),
        if (showExpanded)
          Opacity(
            opacity: t,
            child: AnimatedSwitcher(
              duration: IslandMotion.activitySwapDuration,
              transitionBuilder: _sequentialFadeTransitionBuilder,
              child: KeyedSubtree(
                key: entryKey,
                child: _sizedOverlay(top.expandedBuilder(context, _state), contentSize),
              ),
            ),
          ),
      ],
    );
  }

  /// AnimatedSwitcher's own default transitionBuilder cross-fades: the
  /// outgoing and incoming child are both partially visible for the whole
  /// swap, opacities moving in opposite directions over the same window.
  /// That reads fine when the two look related (a number changing to a
  /// different number), but garbled when they're structurally unrelated —
  /// confirmed live specifically for the stopwatch↔timer handback (30/70
  /// lap-table layout vs. icon/countdown/bar layout), reported as visibly
  /// janky, not just a still-frame artifact.
  ///
  /// This instead fades each child within its own disjoint half of the
  /// animation: whichever one is *leaving* (its own AnimationStatus is
  /// reverse) fades out entirely across [0, 0.5], and whichever is
  /// *entering* (forward) fades in entirely across [0.5, 1] — so only one
  /// of the two is ever visibly non-zero-opacity at a time, a true
  /// sequential fade instead of a simultaneous cross-fade, at the same
  /// total IslandMotion.activitySwapDuration.
  ///
  /// Regression: AnimatedSwitcher calls transitionBuilder exactly once per
  /// entry, at creation — *before* it calls that entry's own
  /// controller.forward()/.reverse() (confirmed by reading
  /// animated_switcher.dart itself, then verifying empirically: a
  /// standalone probe of transitionBuilder's own `animation.status` at
  /// that single call showed AnimationStatus.dismissed for every entry,
  /// outgoing and incoming alike, every time, since neither call has run
  /// yet). Reading `animation.status` directly inside the builder body, as
  /// an earlier version of this did, therefore always saw `dismissed` and
  /// always misclassified the *incoming* child as outgoing — baked in
  /// permanently, since the builder body only runs that once and the
  /// CurvedAnimation it constructs is never rebuilt afterward. Confirmed
  /// live: tapping the island's own timer Pause button forced a
  /// same-instant view-generation bump, and the incoming entry — pinned to
  /// the wrong [0.5, 1] interval, starting from `dismissed` — froze at
  /// opacity 0 for the swap's entire first half, with the outgoing entry
  /// already gone, producing a solid black frame with nothing painted
  /// inside it. AnimatedBuilder here re-invokes this closure on every
  /// frame instead of once, so `animation.status` is read live as the
  /// controller actually ticks (genuinely `.forward`/`.reverse` by then,
  /// not the one-time pre-tick `.dismissed` snapshot).
  static Widget _sequentialFadeTransitionBuilder(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final isOutgoing = animation.status == AnimationStatus.reverse;
        final curved = isOutgoing
            ? CurvedAnimation(parent: animation, curve: const Interval(0.5, 1.0))
            : CurvedAnimation(parent: animation, curve: const Interval(0.0, 0.5));
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  /// Packed contiguously from the pill's right edge inward, in this fixed
  /// priority order (mic, camera, screen capture) — skipping a slot for
  /// whichever indicators are currently invisible rather than reserving
  /// fixed slots for all three regardless of how many are actually
  /// showing. Fixed slots meant mic + screen-capture with camera off left
  /// a visibly empty gap between the two dots that were actually there,
  /// where camera's reserved (but unused) slot used to sit.
  ///
  /// [forceCompact] renders over an activity's own expanded content (see the
  /// call site in `build`) rather than the collapsed pill: there's no "home
  /// state, dots centered" concept once something else's real content is
  /// showing — the dots always sit top-right compact here, same corner
  /// treatment as compact-state on the collapsed pill just against that
  /// box's own, different corner radius (24px, fixed, vs. the collapsed
  /// pill's ~20px — see `build`'s own `radius` calc), so the clearance
  /// constant is its own number, not reused from the collapsed case.
  Widget _privacyDots({bool forceCompact = false}) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _microphoneIndicator.dotTransition,
        _cameraIndicator.dotTransition,
        _screenCaptureIndicator.dotTransition,
        _dotsCompactTransition,
      ]),
      builder: (context, _) {
        final compactT = forceCompact ? 1.0 : Curves.easeInOut.transform(_dotsCompactTransition.value);
        // Home-state (compactT: 0) spacing between dots — unaffected by any
        // of what follows, still the original 12px per slot. Unused when
        // forceCompact, since compactT is pinned to 1 the whole time there.
        const homeSpacing = 12.0;
        // Compact-state horizontal spacing is a separate, smaller number
        // (halving read right once the dots had also shrunk) — but the
        // *closest* dot additionally needs enough total clearance from the
        // right edge to clear the pill's own rounded corner (ClipRRect,
        // ~20px radius at this collapsed size) — 9px was the bare minimum
        // measured to do that at all, but still read as too tight against
        // the border in practice; 13 leaves real breathing room beyond
        // "not clipped," while still clearing content the same way (see
        // PrivacyIndicatorDot's own doc comment for why this is no longer
        // the same number as the vertical inset).
        const compactCornerOffset = 13.0;
        // The expanded card's corner is a fixed, larger 24px radius (vs. the
        // collapsed pill's own ~20px this constant was measured against) —
        // not yet independently verified live against that exact radius;
        // starts from the same value and is the first thing to adjust if it
        // reads clipped or too tight once actually seen expanded.
        const expandedCompactCornerOffset = 13.0;
        const compactInterDotGap = 6.0;
        const compactTopInset = 4.0;
        final effectiveCornerOffset = forceCompact ? expandedCompactCornerOffset : compactCornerOffset;
        final indicators = [
          (_microphoneIndicator, const Color(0xFFFF9F0A), 'Microphone in use.'),
          (_cameraIndicator, const Color(0xFF32D74B), 'Camera in use.'),
          (_screenCaptureIndicator, const Color(0xFFBF5AF2), 'Screen Recording.'),
        ];
        var slot = 0;
        final dots = <Widget>[];
        for (final (indicator, color, label) in indicators) {
          if (indicator.dotTransition.value <= 0) continue;
          slot++;
          dots.add(
            PrivacyIndicatorDot(
              transition: indicator.dotTransition,
              color: color,
              label: label,
              rightOffset: homeSpacing * slot,
              compactRightOffset: effectiveCornerOffset + (slot - 1) * compactInterDotGap,
              compactTopInset: compactTopInset,
              compactT: compactT,
            ),
          );
        }
        return Stack(children: dots);
      },
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
    if (top?.id != _lastTopId) {
      _lastTopId = top?.id;
      _topIdGeneration++;
    }
    // The battery fallback (or nothing registered at all, in principle)
    // is the only case the dots' normal centered position was ever
    // designed for — anything else on top has its own elements roughly
    // where a centered dot would sit.
    final isHomeState = top == null || top.id == 'battery';
    if (isHomeState != _lastIsHomeState) {
      _lastIsHomeState = isHomeState;
      if (isHomeState) {
        _dotsCompactTransition.reverse();
      } else {
        _dotsCompactTransition.forward();
      }
    }
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
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _contentTransition,
                        builder: (context, _) {
                          final contentT = IslandMotion.expansionCurve.transform(_contentTransition.value);
                          return AnimatedContainer(
                            duration: IslandMotion.expansionDuration,
                            curve: IslandMotion.expansionCurve,
                            color: top?.priority == ActivityPriority.ringingEvent ? const Color(0xFF3A1414) : Colors.black,
                            alignment: Alignment.topCenter,
                            child: top == null
                                ? const SizedBox.shrink()
                                : _crossFadedContent(context, top, contentT, contentSize),
                          );
                        },
                      ),
                      // The privacy dots overlay whatever's currently
                      // showing, collapsed or expanded — something as
                      // privacy-sensitive as "is my mic/camera/screen
                      // currently active" shouldn't be able to go invisible
                      // just because the island happens to be expanded to
                      // some other activity's detail view at the time.
                      if (_state == LifecycleState.collapsed ||
                          _state == LifecycleState.hover ||
                          _state == LifecycleState.collapsing)
                        _privacyDots()
                      else
                        _privacyDots(forceCompact: true),
                    ],
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

