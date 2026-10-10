// Reading a view-only wallet QR code at setup (lib/wallet_qr.dart) and the
// Scan wallet QR screen. The screen tests need the native library: run
// `sh tool/fetch_monero_c.sh` first.
//
// No code here holds a real wallet. The format tests use made-up values (an
// address of 1s, a view key of zeros, words repeated) and a stand-in for the
// view key check. The screen tests use random throwaway wallets made when the
// test runs, whose keys are never printed or written into this file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports
import 'package:monero/src/monero.dart';
import 'package:monero/src/wallet2.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/scan_screen.dart';
import 'package:monero_view_wallet/wallet.dart';
import 'package:monero_view_wallet/wallet_qr.dart';

void main() {
  final mainnet = '4${'1' * 94}';
  final stagenet = '5${'1' * 94}';
  final zeros = '0' * 64;
  String gui(String address, {String? query}) =>
      'monero-wallet:$address?${query ?? 'view_key=$zeros&height=1234'}';
  String feather(Map<String, Object?> fields) => jsonEncode({
    'version': 0,
    'primaryAddress': mainnet,
    'privateViewKey': zeros,
    'restoreHeight': 1234,
    'walletName': 'Savings',
    ...fields,
  });
  String words(int n, [String separator = ' ']) =>
      List.filled(n, 'word').join(separator);

  // The view key check, which needs the wallet library, stood in for: it
  // records what it was asked and answers [keyAnswer].
  late List<String> checked;
  String? keyAnswer;
  WalletQr read(String text) => readWalletQr(
    text,
    keysProblem: ({required address, required viewKey}) {
      checked.add(address);
      return keyAnswer;
    },
  );
  setUp(() {
    checked = [];
    keyAnswer = null;
  });
  Refusal? refusal(String text) {
    try {
      read(text);
      return null;
    } on RefusedCode catch (e) {
      return e.reason;
    }
  }

  test("reads the Monero GUI's View Only Wallet code", () {
    expect(read(gui(mainnet)), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 1234,
    ));
    expect(checked, [mainnet]);
    expect(read(gui(stagenet)).address, stagenet);
    // Cake Wallet's spelling, and a scheme a QR reader gave in capitals.
    expect(read('monero_wallet:$mainnet?view_key=$zeros&height=0'), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 0,
    ));
    expect(read(' MONERO-WALLET:$mainnet?height=7&view_key=$zeros\n'), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 7,
    ));
  });

  test("reads Feather's View-Only QR and ignores the wallet's name", () {
    expect(read(feather({})), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 1234,
    ));
    expect(read(feather({'restoreHeight': '99'})).restoreHeight, 99);
    expect(read(feather({'walletName': words(5)})).address, mainnet);
    expect(read(feather({'primaryAddress': stagenet})).address, stagenet);
  });

  test(
    'refuses whole anything with a spend key or seed, before reading it',
    () {
      for (final code in [
        // The GUI's Spendable Wallet code.
        gui(mainnet, query: 'view_key=$zeros&height=1&spend_key=$zeros'),
        gui(mainnet, query: 'spend_key=$zeros&view_key=$zeros&height=1'),
        gui(mainnet, query: 'view_key=$zeros&height=1&Spend_Key=$zeros'),
        gui(mainnet, query: 'view_key=$zeros&height=1&spend%5Fkey=$zeros'),
        gui(mainnet, query: 'view_key=$zeros&height=1&seed=${words(25, '+')}'),
        gui(mainnet, query: 'mnemonic_seed=x&view_key=$zeros&height=1'),
        gui(mainnet, query: 'view_key=$zeros&height=1#spend_key=$zeros'),
        'monero:$mainnet?spend_key=$zeros',
        feather({'privateSpendKey': zeros}),
        feather({'seed': 'x'}),
        feather({
          'keys': {'spend_key': zeros},
        }),
        feather({'walletName': words(12)}),
        // Seed phrases on their own: BIP39, Polyseed and Monero's lengths, in
        // any script and however the words are separated.
        words(12),
        words(16, '\n'),
        words(25),
        words(25, ', '),
        List.filled(25, 'слово').join(' '),
        List.filled(25, '字').join(' '),
        Uri.encodeComponent(words(25)),
        gui(
          mainnet,
          query: 'view_key=$zeros&height=1&note=${words(13, '%20')}',
        ),
      ]) {
        expect(refusal(code), Refusal.spendKey, reason: code);
      }
      // Not even the view key check saw the address.
      expect(checked, isEmpty);
    },
  );

  test('refuses every other code', () {
    for (final code in [
      '',
      'hello',
      words(11),
      // A payment request, an animated key images code, a link.
      'monero:$mainnet?tx_amount=1.5',
      'ur:xmr-output/1-3/lpadaxcsencylobemohsgmoyadhdeynteelblrcygldwvarflojtcywlspdkfmzm',
      'https://example.com/?view_key=$zeros',
      // The GUI's code with a value missing, changed or added.
      'monero-wallet:$mainnet',
      gui(mainnet, query: 'view_key=$zeros'),
      gui(mainnet, query: 'height=1234'),
      gui(mainnet, query: 'view_key=$zeros&height=1234&sk=$zeros'),
      gui(mainnet, query: 'view_key=$zeros&view_key=$zeros&height=1'),
      gui(mainnet, query: 'view_key=$zeros&height=1&'),
      gui(mainnet, query: 'view_key=$zeros&height=-1'),
      gui(mainnet, query: 'view_key=$zeros&height=12a'),
      gui(mainnet, query: 'view_key=$zeros&height=99999999999999999999999'),
      gui(mainnet, query: 'view_key=${'0' * 63}&height=1'),
      gui(mainnet, query: 'view_key=${'g' * 64}&height=1'),
      '${gui(mainnet)}#x',
      'monero-wallet://$mainnet?view_key=$zeros&height=1',
      // Feather's code, changed.
      feather({'version': 1}),
      feather({'version': null}),
      feather({'restoreHeight': 1.5}),
      feather({'restoreHeight': -1}),
      feather({'restoreHeight': null}),
      feather({'privateViewKey': 7}),
      feather({'primaryAddress': null}),
      feather({'other': 1}),
      jsonEncode([feather({})]),
      '{"version":0,',
      // Subaddresses, integrated addresses, and no address at all.
      gui('8${'1' * 94}'),
      gui('7${'1' * 94}'),
      gui('4${'1' * 105}'),
      gui('5${'1' * 105}'),
      gui('4${'1' * 93}0'),
      gui(''),
      feather({'primaryAddress': '8${'1' * 94}'}),
    ]) {
      expect(refusal(code), Refusal.notWalletCode, reason: code);
    }
    expect(checked, isEmpty);
  });

  test('refuses a testnet wallet', () {
    expect(refusal(gui('9${'1' * 94}')), Refusal.testnet);
    expect(
      refusal(feather({'primaryAddress': '9${'1' * 94}'})),
      Refusal.testnet,
    );
    expect(checked, isEmpty);
  });

  test("refuses a key that isn't the address's view key", () {
    keyAnswer = 'view key does not match address';
    expect(refusal(gui(mainnet)), Refusal.keyMismatch);
    keyAnswer = 'failed to verify secret view key';
    expect(refusal(feather({})), Refusal.keyMismatch);
    // An address with a wrong checksum.
    keyAnswer = 'failed to parse address';
    expect(refusal(gui(mainnet)), Refusal.notWalletCode);
  });

  group('Scan wallet QR', () {
    late Wallet2WalletManager manager;
    late Wallet2Wallet full;
    late Wallet2Wallet mainnetFull;

    final address = find.byKey(const Key('address'));
    final viewKey = find.byKey(const Key('viewKey'));
    final restoreHeight = find.byKey(const Key('restoreHeight'));
    final cameraView = find.byKey(const Key('camera'));
    String textIn(WidgetTester tester, Finder field) =>
        tester.widget<TextField>(field).controller!.text;
    bool enabled(WidgetTester tester, String button) =>
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, button))
            .onPressed !=
        null;
    Future<void> phone(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    _FakeCamera useCamera({bool allow = true}) {
      final camera = _FakeCamera(allow: allow);
      qrCamera = camera;
      addTearDown(() => qrCamera = null);
      return camera;
    }

    String guiCode(Wallet2Wallet of, {String? viewKey, String extra = ''}) =>
        'monero-wallet:${of.address()}'
        '?view_key=${viewKey ?? of.secretViewKey()}&height=2345$extra';

    setUpAll(() {
      // Windows looks for DLLs in the current directory.
      Directory.current = 'windows/monero_c';
      manager = MoneroWalletManagerFactory().getWalletManager();
      full = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.stagenet.id,
      );
      expect(full.status(), 0, reason: full.errorString());
      mainnetFull = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.mainnet.id,
      );
      expect(mainnetFull.status(), 0, reason: mainnetFull.errorString());
    });

    testWidgets('setup stays typed where there is no camera', (tester) async {
      await phone(tester);
      await tester.pumpWidget(const MainApp());
      expect(find.text('Watch a wallet'), findsOne);
      expect(find.text('Scan QR code'), findsNothing);
    });

    testWidgets('refuses spend keys and other codes, then fills setup', (
      tester,
    ) async {
      final camera = useCamera();
      final other = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.stagenet.id,
      );
      final otherKey = other.secretViewKey();
      manager.closeWallet(other, false);

      await phone(tester);
      await tester.pumpWidget(const MainApp());
      expect(find.text('Fills all three from the Monero GUI'), findsOne);
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(find.text('Scan wallet QR'), findsOne);
      expect(find.textContaining('Spendable Wallet code'), findsOne);
      expect(cameraView, findsOne);
      expect(find.textContaining('never saved'), findsOne);

      // The GUI's Spendable Wallet code: refused, and the camera goes off.
      camera.show(guiCode(full, extra: '&spend_key=${full.secretSpendKey()}'));
      await tester.pump();
      expect(find.text('That code holds your spend key'), findsOne);
      expect(find.text('Type it in instead'), findsNothing);
      expect(cameraView, findsNothing);
      expect(find.text('Camera paused'), findsOne);
      // Nothing more is read until Scan again.
      camera.show(guiCode(full));
      await tester.pump();
      expect(find.text('That code holds your spend key'), findsOne);

      await tester.tap(find.text('Scan again'));
      await tester.pump();
      expect(cameraView, findsOne);
      expect(find.text('That code holds your spend key'), findsNothing);

      // Another wallet's key with this address is what a spend key looks
      // like to the check.
      camera.show(guiCode(full, viewKey: otherKey));
      await tester.pump();
      expect(find.text("This key isn't this address's view key"), findsOne);
      await tester.tap(find.text('Scan again'));
      await tester.pump();

      camera.show('monero:${full.address()}?tx_amount=1');
      await tester.pump();
      expect(find.text('Not a wallet code'), findsOne);
      expect(find.text('Type it in instead'), findsOne);
      await tester.tap(find.text('Scan again'));
      await tester.pump();

      camera.show(guiCode(full));
      await tester.pumpAndSettle();
      expect(find.text('Watch a wallet'), findsOne);
      expect(textIn(tester, address), full.address());
      expect(textIn(tester, viewKey), full.secretViewKey());
      expect(textIn(tester, restoreHeight), '2345');
      expect(tester.widget<TextField>(viewKey).obscureText, isTrue);
      expect(find.text('Filled from QR code'), findsOne);
      expect(find.text('Matches this address'), findsOne);
      expect(enabled(tester, 'Continue'), isTrue);

      // A changed height keeps the code's mark, a changed address doesn't.
      await tester.enterText(restoreHeight, '2000');
      await tester.pump();
      expect(find.text('Filled from QR code'), findsOne);
      await tester.enterText(address, mainnetFull.address());
      await tester.pump();
      expect(find.text('Filled from QR code'), findsNothing);
      expect(find.text('Fills all three from the Monero GUI'), findsOne);
    });

    testWidgets("reads Feather's code for a mainnet wallet", (tester) async {
      final camera = useCamera();
      await phone(tester);
      await tester.pumpWidget(const MainApp());
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      camera.show(
        jsonEncode({
          'version': 0,
          'primaryAddress': mainnetFull.address(),
          'privateViewKey': mainnetFull.secretViewKey(),
          'restoreHeight': 3100000,
          'walletName': 'Savings',
        }),
      );
      await tester.pumpAndSettle();
      expect(textIn(tester, address), mainnetFull.address());
      expect(textIn(tester, restoreHeight), '3100000');
      expect(find.text('Matches this address'), findsOne);
      expect(find.text('Filled from QR code'), findsOne);
    });

    testWidgets('says when the camera is off, and goes back to typing', (
      tester,
    ) async {
      final camera = useCamera(allow: false);
      await phone(tester);
      await tester.pumpWidget(const MainApp());
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(find.text('The camera is off for this app.'), findsOne);
      expect(cameraView, findsNothing);
      await tester.tap(find.text('Open Settings'));
      expect(camera.settingsOpened, 1);
      await tester.tap(find.text('Type it in instead'));
      await tester.pumpAndSettle();
      expect(find.text('Watch a wallet'), findsOne);
      expect(find.text('Fills all three from the Monero GUI'), findsOne);
      expect(textIn(tester, address), isEmpty);
    });
  });
}

/// Stands in for the iPhone's camera: [show] is a code held up to it.
class _FakeCamera implements QrCamera {
  _FakeCamera({required this.allow});

  final bool allow;
  int settingsOpened = 0;
  ValueChanged<String>? _onCode;

  @override
  Future<bool> allowed() async => allow;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Widget view(ValueChanged<String> onCode) {
    _onCode = onCode;
    return const SizedBox.expand(key: Key('camera'));
  }

  void show(String code) => _onCode!(code);
}
