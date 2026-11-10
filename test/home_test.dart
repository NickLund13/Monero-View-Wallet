// Home's states and the transaction screen. Needs the native library: run
// `sh tool/fetch_monero_c.sh` first.
//
// The wallet is a random throwaway made when the test runs, held in memory.
// Balances, heights and transactions are made up and set on the session by
// hand; no node is contacted. Transaction IDs are runs of one digit.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports
import 'package:monero/src/monero.dart';
import 'package:monero/src/wallet2.dart';
import 'package:monero_view_wallet/home_screen.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/price.dart';
import 'package:monero_view_wallet/session.dart';
import 'package:monero_view_wallet/ui.dart';
import 'package:monero_view_wallet/wallet.dart';

void main() {
  late Wallet2Wallet full;

  ViewWallet watch() => ViewWallet.create(
    address: full.address(),
    viewKey: full.secretViewKey(),
    restoreHeight: 0,
  );

  // Text as drawn, without what a screen reader says in place of dots.
  Finder shown(String text) => find.byWidgetPredicate(
    (w) =>
        w is RichText &&
        w.text.toPlainText(includeSemanticsLabels: false) == text,
  );

  // Tall enough that no screen has to scroll.
  Future<void> phone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  setUpAll(() {
    // Windows looks for DLLs in the current directory.
    Directory.current = 'windows/monero_c';
    final manager = MoneroWalletManagerFactory().getWalletManager();
    full = manager.createWallet(
      path: '',
      password: '',
      networkType: Network.stagenet.id,
    );
    expect(full.status(), 0, reason: full.errorString());
  });

  // Synced to block 2000, as after the first scan.
  _Session synced() => _Session(watch())
    ..synced = true
    ..scanned = true
    ..height = 2000
    ..nodeHeight = 2000;

  testWidgets('Home says when it is connecting to the node or catching up', (
    tester,
  ) async {
    // Opened from its file: the first scan was done on an earlier launch.
    final session = _Session(watch())
      ..scanned = true
      ..height = 2000;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(find.text('Connecting to your node…'), findsOne);
    expect(find.byType(LinearProgressIndicator), findsOne);

    session
      ..nodeHeight = 3204
      ..changed();
    await tester.pump();
    expect(find.text('Catching up · 1204 blocks to go'), findsOne);

    session
      ..synced = true
      ..nodeHeight =
          2001 // one behind is normal as a block arrives
      ..changed();
    await tester.pump();
    expect(find.textContaining('Synced to block 2000'), findsOne);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // A node slow to answer again, as after the app was in the background,
    // is no alarm yet.
    session
      ..connecting = true
      ..changed();
    await tester.pump();
    expect(find.text('Connecting to your node…'), findsOne);
    expect(find.byType(LinearProgressIndicator), findsOne);
    expect(find.textContaining("Can't reach your node"), findsNothing);
    expect(find.text('Change node'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Home shows the last key images import, and outputs since', (
    tester,
  ) async {
    const imported = (total: 5, spent: 2, withoutKeyImage: 0);
    final session = synced()
      ..outputs = imported
      ..lastImport = KeyImageImport(
        at: DateTime(2026, 10, 3, 9, 5),
        fileName: 'key_images',
        newlySpent: 2,
        outputs: imported,
      );
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(find.text('Key images imported 3 Oct 2026'), findsOne);

    await tester.tap(find.text('Key images imported 3 Oct 2026'));
    await tester.pumpAndSettle();
    expect(find.text('LAST IMPORT'), findsOne);
    expect(find.text('3 Oct 2026, 09:05'), findsOne);
    expect(find.text('Newly spent'), findsOne);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    session
      ..outputs = (total: 8, spent: 2, withoutKeyImage: 3)
      ..changed();
    await tester.pump();
    expect(find.text('3 new outputs since your key images'), findsOne);
    expect(find.text('Import'), findsOne);

    // Dismissed until another output comes.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Key images imported 3 Oct 2026'), findsOne);
    session
      ..outputs = (total: 9, spent: 2, withoutKeyImage: 4)
      ..changed();
    await tester.pump();
    expect(find.text('4 new outputs since your key images'), findsOne);

    await tester.pumpWidget(const SizedBox());
  });

  test('long waits read in hours', () {
    expect(minutesAndHours(4), '4 min');
    expect(minutesAndHours(60), '1 h');
    expect(minutesAndHours(125), '2 h 5 min');
  });

  testWidgets('Home names the wallet as the person calls it', (tester) async {
    final session = synced();
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(find.text('Monero wallet'), findsOne);
    expect(find.text("View only · can't send"), findsOne);

    await tester.tap(find.byTooltip('Rename this wallet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('walletName')), 'Savings');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Savings'), findsOne);
    expect(session.name, 'Savings');

    // Cancel keeps it; an empty name goes back to the default.
    await tester.tap(find.byTooltip('Rename this wallet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('walletName')), 'Other');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Savings'), findsOne);
    await tester.tap(find.byTooltip('Rename this wallet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('walletName')), ' ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Monero wallet'), findsOne);

    await tester.pumpWidget(const SizedBox());
  });

  test('the wallet keeps its name in its file', () async {
    final wallet = watch();
    addTearDown(wallet.close);
    final first = WalletSession(wallet);
    expect(first.name, 'Monero wallet');
    await first.rename('  Savings ');
    expect(first.name, 'Savings');
    expect(wallet.remembered('mvw.name'), 'Savings');
    expect(WalletSession(wallet).name, 'Savings');
    await first.rename('');
    expect(WalletSession(wallet).name, 'Monero wallet');
  });

  testWidgets('the eye button hides every amount, on Home and a transaction', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final session = synced()
      ..balance = 2500000000000
      ..unlocked = 1500000000000
      ..transfers = [
        Transfer(
          incoming: true,
          amount: 1000000000000,
          height: 1900,
          confirmations: 100,
          time: DateTime(2026, 10, 2),
          subaddresses: {0},
        ),
        Transfer(
          incoming: false,
          amount: 1200000000000,
          height: 1500,
          confirmations: 500,
          time: DateTime(2026, 9, 30),
          fee: 31200000,
          hash: '3' * 64,
        ),
      ];
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(find.text('2.5000 XMR'), findsOne);
    expect(find.textContaining('1.5000 unlocked'), findsOne);
    expect(find.text('+1.0000'), findsOne);
    expect(find.text('−1.2000'), findsOne);

    await tester.tap(find.byTooltip('Hide balance'));
    await tester.pump();
    expect(session.hideAmounts, isTrue);
    expect(find.textContaining('2.5000'), findsNothing);
    expect(shown('$hiddenAmount XMR'), findsOne);
    expect(find.text('$hiddenAmount unlocked'), findsOne);
    expect(find.text(hiddenAmount), findsNWidgets(2));
    expect(find.textContaining('1.0000'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Balance hidden')), findsOne);
    expect(find.byTooltip('Show balance'), findsOne);

    // The transaction screen follows, the fee too.
    await tester.tap(find.text('30 Sep 2026 · found via key images'));
    await tester.pumpAndSettle();
    expect(shown('$hiddenAmount XMR'), findsOne);
    expect(find.bySemanticsLabel(RegExp('Amount hidden')), findsOne);
    expect(find.text(hiddenAmount), findsOne, reason: 'the fee');
    expect(find.textContaining('1.2000'), findsNothing);
    expect(find.text('0.0000312'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show balance'));
    await tester.pump();
    expect(session.hideAmounts, isFalse);
    expect(find.text('2.5000 XMR'), findsOne);
    expect(find.text('+1.0000'), findsOne);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Home opens in the currency last chosen', (tester) async {
    usdPrice.fetch = () async => 200; // a made-up price
    usdPrice.on = true;
    addTearDown(() {
      usdPrice.on = false;
      usdPrice.fetch = fetchXmrUsd;
    });
    final session = synced()
      ..balance = 2500000000000
      ..unlocked = 1500000000000
      ..showUsd = true;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    await tester.pump();
    expect(find.text('500.00 USD'), findsOne);
    expect(find.text('tap for XMR'), findsOne);

    await tester.tap(find.text('500.00 USD'));
    await tester.pump();
    expect(find.text('2.5000 XMR'), findsOne);
    expect(session.showUsd, isFalse);

    // With the price lookup off, XMR, also once it is on again.
    await tester.tap(find.text('2.5000 XMR'));
    await tester.pump();
    expect(session.showUsd, isTrue);
    usdPrice.on = false;
    await tester.pump();
    expect(find.text('2.5000 XMR'), findsOne);
    expect(session.showUsd, isFalse);
    usdPrice.on = true;
    await tester.pump();
    expect(find.text('2.5000 XMR'), findsOne);
    usdPrice.on = false; // stops the refresh timer before the test ends

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'the wallet keeps the currency and hidden amounts in its file',
    () async {
      final wallet = watch();
      addTearDown(wallet.close);
      final first = WalletSession(wallet);
      expect(first.showUsd, isFalse);
      expect(first.hideAmounts, isFalse);
      await first.setShowUsd(true);
      await first.setHideAmounts(true);
      final next = WalletSession(wallet);
      expect(next.showUsd, isTrue);
      expect(next.hideAmounts, isTrue);
      await next.setShowUsd(false);
      await next.setHideAmounts(false);
      expect(WalletSession(wallet).showUsd, isFalse);
      expect(WalletSession(wallet).hideAmounts, isFalse);
    },
  );

  testWidgets('Home says which address each payment went to', (tester) async {
    final session = synced();
    final wallet = session.wallet;
    while (wallet.subaddressCount <= 3) {
      wallet.addSubaddress();
    }
    wallet.setLabel(3, 'Rent from Alex');
    Transfer received(
      Set<int> to, {
      int confirmations = 100,
      bool mined = false,
    }) => Transfer(
      incoming: true,
      amount: 1000000000000,
      height: 1900,
      confirmations: confirmations,
      time: DateTime(2026, 10, 2),
      subaddresses: to,
      mined: mined,
      // Its own ID, so the transaction screen finds it again.
      hash: mined ? '6' * 64 : '',
    );
    session.transfers = [
      received({0}),
      received({2}),
      received({3}),
      received({1}, confirmations: 4),
      received({}), // to another account
      received({1}, confirmations: 25, mined: true),
    ];
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(find.text('2 Oct 2026 · primary address'), findsOne);
    expect(find.text('2 Oct 2026 · subaddress #2'), findsOne);
    expect(find.text('2 Oct 2026 · Rent from Alex'), findsOne);
    // Where it went shows once it has unlocked.
    expect(find.text('4 of 10 confirmations'), findsOne);
    expect(find.text('2 Oct 2026'), findsOne);
    // A block reward, as mining pays, unlocks after 60 blocks.
    expect(find.text('25 of 60 confirmations'), findsOne);

    // The transaction screen counts the same.
    await tester.tap(find.text('25 of 60 confirmations'));
    await tester.pumpAndSettle();
    expect(find.text('25 of 60'), findsOne);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a spend on Home shows its fee, block and ID', (
    tester,
  ) async {
    String? clipboard;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final id = '1' * 64;
    Transfer spend(int confirmations) => Transfer(
      incoming: false,
      amount: 1200000000000,
      height: 1500,
      confirmations: confirmations,
      time: DateTime(2026, 10, 2, 18, 7),
      fee: 31200000,
      hash: id,
    );
    final session = synced()..transfers = [spend(8640)];
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));

    await tester.tap(find.text('2 Oct 2026 · found via key images'));
    await tester.pumpAndSettle();
    expect(find.text('Sent'), findsOne);
    expect(find.text('−1.2000 XMR'), findsOne);
    expect(find.text('2 Oct 2026, 18:07'), findsOne);
    expect(find.text('0.0000312'), findsOne);
    expect(find.text('8,640'), findsOne);
    expect(find.text('1,500'), findsOne);
    expect(find.text('Primary account'), findsOne);
    expect(find.text(id), findsOne);
    expect(find.textContaining('Found through imported key images'), findsOne);

    await tester.tap(find.byTooltip('Copy transaction ID'));
    await tester.pump();
    expect(clipboard, id);
    expect(find.byTooltip('Copied'), findsOne);

    // The confirmations go up while the screen is open.
    session
      ..transfers = [spend(8641)]
      ..changed();
    await tester.pump();
    expect(find.text('8,641'), findsOne);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Monero wallet'), findsOne);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a payment still in the pool shows where it went, and no fee', (
    tester,
  ) async {
    final session = synced();
    final wallet = session.wallet;
    while (wallet.subaddressCount <= 2) {
      wallet.addSubaddress();
    }
    wallet.setLabel(2, 'Rent from Alex');
    Transfer payment({required int height, required int confirmations}) =>
        Transfer(
          incoming: true,
          amount: 571000000000,
          height: height,
          confirmations: confirmations,
          time: DateTime(2026, 10, 9, 8, 30),
          subaddresses: {2},
          fee: 31200000,
          hash: '2' * 64,
        );
    session.transfers = [payment(height: 0, confirmations: 0)];
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));

    await tester.tap(find.text('Pending'));
    await tester.pumpAndSettle();
    expect(find.text('Received'), findsOne);
    expect(find.text('+0.5710 XMR'), findsOne);
    expect(find.text('Subaddress #2 · Rent from Alex'), findsOne);
    expect(find.text('None yet'), findsOne);
    expect(find.text('Not in a block yet'), findsOne);
    expect(find.text('Fee'), findsNothing, reason: 'the sender paid it');
    expect(find.textContaining('key images'), findsNothing);

    // Mined, then the same entry again with its first confirmations.
    session
      ..transfers = [payment(height: 2001, confirmations: 1)]
      ..changed();
    await tester.pump();
    expect(find.text('1 of 10'), findsOne);
    expect(find.text('2,001'), findsOne);

    await tester.pumpWidget(const SizedBox());
  });
}

/// A session on a made-up node that a test can redraw by hand.
class _Session extends WalletSession {
  _Session(super.wallet);

  @override
  String get node => 'node.example.org:38081';

  /// True for a node that hasn't answered the last polls, when a test says
  /// so.
  @override
  bool connecting = false;

  /// Redraws the screens after the test changed what the session knows.
  void changed() => notifyListeners();
}
