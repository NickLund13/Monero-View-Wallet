// The lock screen and when the app locks, with a stand-in for Face ID, Touch
// ID and the passcode (fake_check.dart). No wallet library needed: a made-up
// balance stands in for Home.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/lock.dart';
import 'package:monero_view_wallet/main.dart';

import 'fake_check.dart';

void main() {
  late FakeCheck check;
  late DateTime clock;

  setUp(() {
    check = FakeCheck(Unlock.faceId);
    clock = DateTime(2026, 10, 9, 12);
    appLock = AppLock()
      ..check = check
      ..now = () => clock;
  });
  tearDown(() => appLock = AppLock());

  const balance = '2.5000 XMR'; // made up
  Future<void> showApp(WidgetTester tester) async {
    // In front, as at launch.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      const MainApp(
        home: Scaffold(body: Center(child: Text(balance))),
      ),
    );
    // The lock asks by itself after the first frame, and shows the answer in
    // the next.
    await tester.pump();
    await tester.pump();
  }

  void change(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  const goAway = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const comeBack = [AppLifecycleState.hidden, AppLifecycleState.inactive];

  bool locked() => find.text('Wallet locked').evaluate().isNotEmpty;

  testWidgets(
    'opens locked, asks for Face ID by itself, and hides the wallet',
    (tester) async {
      await appLock.start(on: true);
      expect(appLock.locked, isTrue, reason: 'locked before the first frame');
      final semantics = tester.ensureSemantics();
      await showApp(tester);
      expect(check.asked, [false], reason: 'Face ID, once, without a tap');

      // Cancelled: still locked, and nothing to complain about.
      expect(locked(), isTrue);
      expect(find.text(balance), findsNothing);
      expect(find.semantics.byLabel(balance), findsNothing);
      expect(
        find.text(balance, skipOffstage: false),
        findsOne,
        reason: 'kept as it was behind the lock',
      );
      expect(find.textContaining('Try again'), findsNothing);
      expect(find.text('Use passcode'), findsOne);

      check.answers.add(CheckResult.ok);
      await tester.tap(find.text('Unlock with Face ID'));
      await tester.pump();
      expect(check.asked, [false, false]);
      expect(locked(), isFalse);
      expect(find.text(balance), findsOne);
      expect(find.semantics.byLabel(balance), findsOne);
      semantics.dispose();
    },
  );

  testWidgets('locks again only after a minute in the background', (
    tester,
  ) async {
    check.answers.add(CheckResult.ok);
    await appLock.start(on: true);
    await showApp(tester);
    expect(locked(), isFalse);

    // Face ID's own sheet makes the app inactive for a moment.
    change(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump();
    expect(locked(), isFalse);

    change(tester, goAway);
    clock = clock.add(const Duration(seconds: 59));
    change(tester, [...comeBack, AppLifecycleState.resumed]);
    await tester.pump();
    expect(locked(), isFalse);
    expect(check.asked, hasLength(1));

    change(tester, goAway);
    clock = clock.add(lockAfter);
    change(tester, comeBack);
    await tester.pump();
    expect(locked(), isTrue, reason: 'up before the app is in front again');
    expect(find.text(balance), findsNothing);
    expect(check.asked, hasLength(1), reason: 'iOS refuses a check behind');
    check.answers.add(CheckResult.ok);
    change(tester, [AppLifecycleState.resumed]);
    await tester.pump();
    expect(check.asked, hasLength(2));
    expect(locked(), isFalse);

    // A clock set back while away can't hide how long the app was gone.
    change(tester, goAway);
    clock = clock.subtract(const Duration(hours: 1));
    change(tester, [...comeBack, AppLifecycleState.resumed]);
    await tester.pump();
    expect(locked(), isTrue);
  });

  testWidgets('says what to do when Face ID fails, and offers the passcode', (
    tester,
  ) async {
    check.answers.addAll([
      CheckResult.failed,
      CheckResult.lockedOut,
      CheckResult.unavailable,
      CheckResult.ok,
    ]);
    await appLock.start(on: true);
    await showApp(tester);
    expect(
      find.text(
        "Face ID didn't recognise you. Try again, or use your passcode.",
      ),
      findsOne,
    );
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pump();
    expect(
      find.text('Face ID is off after too many tries. Use your passcode.'),
      findsOne,
    );
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pump();
    expect(find.text("Face ID isn't available. Use your passcode."), findsOne);

    await tester.tap(find.text('Use passcode'));
    await tester.pump();
    expect(check.asked, [false, false, false, true]);
    expect(locked(), isFalse);
  });

  testWidgets('with Touch ID or only a passcode, the buttons say so', (
    tester,
  ) async {
    check.unlock = Unlock.touchId;
    await appLock.start(on: true);
    await showApp(tester);
    expect(find.text('Unlock with Touch ID'), findsOne);
    expect(find.text('Use passcode'), findsOne);

    // Face ID turned off for the app while it was away.
    check.unlock = Unlock.passcode;
    await tester.tap(find.text('Unlock with Touch ID'));
    await tester.pump();
    expect(check.asked.last, isTrue, reason: 'the passcode');
    expect(find.text('Unlock with passcode'), findsOne);
    expect(find.text('Use passcode'), findsNothing);
  });

  testWidgets('never locks with the lock off, or where nothing can check', (
    tester,
  ) async {
    await appLock.start(on: false);
    await showApp(tester);
    change(tester, goAway);
    clock = clock.add(const Duration(hours: 1));
    change(tester, [...comeBack, AppLifecycleState.resumed]);
    await tester.pump();
    expect(locked(), isFalse);
    expect(check.asked, isEmpty);

    // An iPhone with no passcode, and the Windows test build.
    for (final noCheck in [FakeCheck(Unlock.none), const NoOwnerCheck()]) {
      appLock = AppLock()..check = noCheck;
      await appLock.start(on: true);
      expect(appLock.locked, isFalse);
      expect(appLock.canLock, isFalse);
    }
  });

  testWidgets("lets the owner in once the iPhone's passcode is gone", (
    tester,
  ) async {
    // Only someone who knows the passcode can take it off, and without one
    // there is nothing left to check with.
    await appLock.start(on: true);
    await showApp(tester);
    expect(locked(), isTrue);
    check.unlock = Unlock.none;
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pump();
    expect(locked(), isFalse);
    expect(check.asked, [false], reason: 'only the check at launch');
  });

  testWidgets('still starts, locked, when the check is broken', (tester) async {
    check.broken = true;
    await appLock.start(on: true);
    expect(appLock.locked, isTrue);
    await showApp(tester);
    expect(find.text("The check didn't start. Try again."), findsOne);
    expect(find.text(balance), findsNothing);

    check
      ..broken = false
      ..answers.add(CheckResult.ok);
    await tester.tap(find.text('Unlock with passcode'));
    await tester.pump();
    expect(locked(), isFalse);
    expect(check.asked, [false], reason: 'Face ID, now it answers');
  });

  test('turning the lock off needs the owner', () async {
    check.answers.addAll([CheckResult.cancelled, CheckResult.ok]);
    expect(await appLock.confirm(), isFalse);
    expect(await appLock.confirm(), isTrue);
    expect(check.asked, [true, true], reason: 'Face ID or the passcode');
    check.broken = true;
    expect(await appLock.confirm(), isFalse);
  });
}
