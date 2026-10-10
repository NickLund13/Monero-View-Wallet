/// Screen 11 of the design: the lock. With a wallet on the iPhone or an
/// Android phone, the app opens locked, and locks again when it comes back
/// after [lockAfter] or more in the background. Face ID, Touch ID or the
/// iPhone's passcode unlocks it; on Android the phone's fingerprint or face,
/// or its screen lock.
///
/// The checks are the phone's own: Apple's LocalAuthentication, called from
/// ios/Runner/AppDelegate.swift, and Android's BiometricPrompt, called from
/// android/app/src/main/kotlin/com/example/monero_view_wallet/AppLock.kt. The
/// app never sees a face, a fingerprint, the passcode or the screen lock, only
/// whether the check passed. The lock hides the balance and history; it
/// doesn't encrypt anything. On the iPhone the wallet's files are encrypted
/// with a password the Keychain only gives out while the iPhone is unlocked.
///
/// The Runner also covers the app whenever it isn't active on the iPhone, and
/// whenever it is out of sight on Android, where Recents never shows a picture
/// of it either: locked or not, the app switcher shows nothing of the wallet.
/// The cover stays on when the app is back in front until the app has drawn
/// itself as it is now, so the balance from before it went away never shows,
/// not even for a frame.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

/// How long the app can be in the background before it locks.
const lockAfter = Duration(minutes: 1);

/// What the device unlocks the app with.
enum Unlock {
  faceId('Face ID'),
  touchId('Touch ID'),

  /// The passcode only: the iPhone has no Face ID or Touch ID set up, or it is
  /// turned off for this app.
  passcode('Passcode'),

  /// Nothing: an iPhone with no passcode, where the app can't lock, or a build
  /// that can't ask (the Windows test build).
  none('Face ID'),

  /// On Android: the phone's fingerprint, or its face, or either on a phone
  /// that has both, when Android counts it as strong (Class 3) and one is set
  /// up.
  fingerprint('Fingerprint', android: true),
  face('Face unlock', android: true),
  fingerprintOrFace('Fingerprint or face', android: true),

  /// On Android: the screen lock only (a PIN, pattern or password).
  screenLock('Screen lock', android: true),

  /// On Android: nothing, on a phone with no screen lock.
  noScreenLock('Screen lock', android: true);

  const Unlock(this.label, {this.android = false});

  /// As a title: "Face ID to open".
  final String label;
  final bool android;

  /// Within a sentence: "Unlock with Face ID", "Unlock with fingerprint".
  String get inSentence => android ? label.toLowerCase() : label;

  /// Face ID, Touch ID, or Android's fingerprint or face: asked for first,
  /// with the passcode or screen lock to fall back on.
  bool get biometric => switch (this) {
    faceId || touchId || fingerprint || face || fingerprintOrFace => true,
    _ => false,
  };

  /// The app can't lock with it.
  bool get nothing => this == none || this == noScreenLock;

  /// What the lock falls back on: the iPhone's passcode, or Android's screen
  /// lock.
  String get fallback => android ? 'screen lock' : 'passcode';
}

/// The answer to one check.
enum CheckResult {
  ok,

  /// The person, or the phone, closed the check. Nothing to say about it.
  cancelled,
  failed,

  /// Face ID or Touch ID, or Android's fingerprint or face, is off after too
  /// many failed tries, until the passcode or screen lock is entered.
  lockedOut,

  /// Face ID or Touch ID is not set up, or turned off for this app; or
  /// Android's fingerprint or face isn't set up any more.
  unavailable,

  /// The iPhone has no passcode any more, or the Android phone no screen lock.
  noPasscode,
}

/// The device's own check that its owner is holding it.
abstract interface class OwnerCheck {
  Future<Unlock> kind();

  /// Face ID or Touch ID (on Android the fingerprint or face), or with
  /// [passcode] the passcode or screen lock, where the phone first tries the
  /// face or fingerprint if it can. [reason] is shown with the check.
  Future<CheckResult> ask({required String reason, required bool passcode});
}

/// The phone's check, through the Runner: ios/Runner/AppDelegate.swift on the
/// iPhone, AppLock.kt on Android.
class PhoneOwnerCheck implements OwnerCheck {
  const PhoneOwnerCheck();

  static const _channel = MethodChannel('monero_view_wallet/lock');

  @override
  Future<Unlock> kind() async =>
      switch (await _channel.invokeMethod<String>('kind')) {
        'faceID' => Unlock.faceId,
        'touchID' => Unlock.touchId,
        'none' => Unlock.none,
        'fingerprint' => Unlock.fingerprint,
        'face' => Unlock.face,
        'biometric' => Unlock.fingerprintOrFace,
        'screenLock' => Unlock.screenLock,
        'noScreenLock' => Unlock.noScreenLock,
        _ => Platform.isAndroid ? Unlock.screenLock : Unlock.passcode,
      };

  @override
  Future<CheckResult> ask({
    required String reason,
    required bool passcode,
  }) async {
    final answer = await _channel.invokeMethod<String>('ask', {
      'reason': reason,
      'passcode': passcode,
    });
    return CheckResult.values.firstWhere(
      (result) => result.name == answer,
      orElse: () => CheckResult.failed,
    );
  }
}

/// Where there is no check to ask, as in the Windows test build: the app
/// doesn't lock.
class NoOwnerCheck implements OwnerCheck {
  const NoOwnerCheck();

  @override
  Future<Unlock> kind() async => Unlock.none;

  @override
  Future<CheckResult> ask({
    required String reason,
    required bool passcode,
  }) async => CheckResult.noPasscode;
}

/// Whether the app is locked, and when it locks. [LockGate] shows it.
class AppLock extends ChangeNotifier {
  /// The device's check. A test puts a stand-in here.
  OwnerCheck check = Platform.isIOS || Platform.isAndroid
      ? const PhoneOwnerCheck()
      : const NoOwnerCheck();

  /// The time now. A test can move it on.
  DateTime Function() now = DateTime.now;

  /// Takes the Runner's cover off the app (ios/Runner/AppDelegate.swift,
  /// AppLock.kt on Android). A test puts a stand-in here.
  Future<void> Function() uncover = Platform.isIOS || Platform.isAndroid
      ? () => PhoneOwnerCheck._channel.invokeMethod<void>('uncover')
      : () async {};

  /// What the device unlocks with, as of the last check.
  Unlock kind = Unlock.none;

  /// Settings → Face ID to open, for the wallet being watched (the wallet's
  /// file keeps it, see WalletSession.lockOn). False while there is no wallet.
  bool get on => _on;
  set on(bool value) {
    _on = value;
    notifyListeners();
  }

  bool _on = false;

  bool get canLock => !kind.nothing;

  /// The lock screen is up, and the rest of the app hidden.
  bool get locked => _locked;
  bool _locked = false;

  /// A check is showing.
  bool get asking => _asking;
  bool _asking = false;

  /// Why the last check didn't unlock, for the lock screen.
  String? get problem => _problem;
  String? _problem;

  DateTime? _awaySince;
  bool _askWhenShown = false;

  /// At launch: learns what the device unlocks with and, if the lock is [on],
  /// locks before the first frame, so the balance never shows unchecked.
  Future<void> start({required bool on}) async {
    try {
      kind = await check.kind();
    } on Exception {
      // Can't tell: lock all the same, and still let the app start. The lock
      // screen asks again when the owner taps Unlock.
      kind = Platform.isAndroid ? Unlock.screenLock : Unlock.passcode;
    }
    _on = on;
    if (on && canLock) _lock();
  }

  void _lock() {
    _locked = true;
    _problem = null;
    _askWhenShown = true;
    // Nothing behind the lock screen keeps the keyboard up.
    FocusManager.instance.primaryFocus?.unfocus();
    notifyListeners();
  }

  /// Follows the app into and out of the background. Coming back starts with
  /// "inactive", while the Runner's cover is still on, so the lock is up by
  /// the time the app shows. On Android a new activity for the app that is
  /// already running goes from "detached" straight to "resumed", under the
  /// cover too.
  void lifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _awaySince ??= now();
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        final away = _awaySince;
        _awaySince = null;
        if (away != null && on && canLock && !locked) {
          final gone = now().difference(away);
          // A clock set back while the app was away counts as a long time.
          if (gone.isNegative || gone >= lockAfter) _lock();
        }
        if (state == AppLifecycleState.resumed) {
          askIfDue();
          _uncoverWhenDrawn();
        }
    }
  }

  /// Takes the cover off once the app has drawn itself as it is now, the lock
  /// screen if it just locked: after two frames, so the first is on the
  /// screen.
  void _uncoverWhenDrawn() {
    final binding = WidgetsBinding.instance;
    binding.endOfFrame
        .then((_) => binding.endOfFrame)
        .then((_) => uncover())
        .ignore();
  }

  /// Starts the check once each time the lock screen comes up, so it takes no
  /// tap. Only while the app is in front: the phone refuses a check behind it.
  void askIfDue() {
    if (!locked || !_askWhenShown) return;
    _askWhenShown = false;
    unlock();
  }

  /// Asks for Face ID or Touch ID (on Android the fingerprint or face), or
  /// with [passcode] the passcode or screen lock, and unlocks if it passes.
  Future<void> unlock({bool passcode = false}) async {
    if (!locked || asking) return;
    _asking = true;
    _problem = null;
    notifyListeners();
    try {
      // Face ID can be turned off, or locked out, while the app is away.
      kind = await check.kind();
      final withPasscode = passcode || !kind.biometric;
      final result = kind.nothing
          ? CheckResult.noPasscode
          : await check.ask(
              reason: 'Unlock your wallet',
              passcode: withPasscode,
            );
      final face = kind.label;
      final fallback = kind.fallback;
      switch (result) {
        case CheckResult.ok:
          _locked = false;
        // Only the owner can take the passcode off an iPhone, or the screen
        // lock off an Android phone, and without one there is nothing to
        // check with: don't shut them out.
        case CheckResult.noPasscode:
          kind = kind.android ? Unlock.noScreenLock : Unlock.none;
          _locked = false;
        case CheckResult.cancelled:
          break;
        case CheckResult.failed:
          _problem = withPasscode
              ? "That didn't unlock it. Try again."
              : "$face didn't recognise you. Try again, or use your "
                    '$fallback.';
        case CheckResult.lockedOut:
          _problem = '$face is off after too many tries. Use your $fallback.';
        case CheckResult.unavailable:
          _problem = "$face isn't available. Use your $fallback.";
      }
    } on Exception {
      _problem = "The check didn't start. Try again.";
    } finally {
      _asking = false;
      notifyListeners();
    }
  }

  /// Asks the owner before Settings turns the lock off. True if the check
  /// passed, or the device has nothing to check with.
  Future<bool> confirm() async {
    try {
      final result = await check.ask(
        reason: 'Turn off the lock',
        passcode: true,
      );
      return result == CheckResult.ok || result == CheckResult.noPasscode;
    } on Exception {
      return false;
    }
  }
}

/// The lock the app uses. main() starts it. A test puts a new one here before
/// it shows the app.
AppLock appLock = AppLock();

/// Puts the lock screen over the whole app, its pushed screens and dialogs
/// included, while [appLock] is locked. What is behind stays as it was, but
/// isn't drawn, can't be tapped or focused, and screen readers don't see it.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  /// The app's navigator.
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: appLock.lifecycleChanged);
    // Already in front at launch: no "resumed" will come.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        appLock.askIfDue();
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appLock,
    builder: (context, child) {
      final locked = appLock.locked;
      return Stack(
        fit: StackFit.expand,
        children: [
          // Always first, so locking never rebuilds the app behind.
          Offstage(
            offstage: locked,
            child: TickerMode(
              enabled: !locked,
              child: ExcludeFocus(excluding: locked, child: child!),
            ),
          ),
          if (locked) const LockScreen(),
        ],
      );
    },
    child: widget.child,
  );
}

class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appLock,
    builder: (context, _) => _screen(context),
  );

  Widget _screen(BuildContext context) {
    final c = context.colors;
    final lock = appLock;
    final biometric = lock.kind.biometric;
    final problem = lock.problem;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 28),
          child: Column(
            children: [
              const Spacer(flex: 5),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: c.card,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline, size: 38, color: c.accentText),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: const Text(
                  'Wallet locked',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  'Unlock to see your balance and history. The app locks '
                  'again after a minute in the background.',
                  textAlign: TextAlign.center,
                  style: context.body,
                ),
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      problem,
                      textAlign: TextAlign.center,
                      style: context.caption.copyWith(color: c.red),
                    ),
                  ),
                ),
              const Spacer(flex: 7),
              FilledButton.icon(
                onPressed: lock.asking ? null : lock.unlock,
                icon: Icon(switch (lock.kind) {
                  Unlock.faceId || Unlock.face => Icons.face_unlock_outlined,
                  Unlock.touchId ||
                  Unlock.fingerprint ||
                  Unlock.fingerprintOrFace => Icons.fingerprint,
                  _ => Icons.dialpad,
                }, size: 20),
                label: Text(
                  'Unlock with '
                  '${biometric ? lock.kind.inSentence : lock.kind.fallback}',
                ),
              ),
              const SizedBox(height: 8),
              if (biometric)
                TextButton(
                  onPressed: lock.asking
                      ? null
                      : () => lock.unlock(passcode: true),
                  child: Text('Use ${lock.kind.fallback}'),
                )
              else
                const SizedBox(height: 44),
            ],
          ),
        ),
      ),
    );
  }
}
