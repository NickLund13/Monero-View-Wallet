// Reading a view-only wallet QR code, or an address or view key alone, at
// setup (lib/wallet_qr.dart) and the Scan wallet QR screen. The screen tests need the native library: run
// `sh tool/fetch_monero_c.sh` first.
//
// No code here holds a real wallet. The format tests use made-up values (an
// address of 1s, a view key of zeros, words repeated) and a stand-in for the
// view key check. The screen tests use random throwaway wallets made when the
// test runs, whose keys are never printed or written into this file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Future<WalletQr> read(String text, {String? address}) => readWalletQr(
    text,
    address: address,
    keysProblem: ({required address, required viewKey}) async {
      checked.add(address);
      return keyAnswer;
    },
  );
  setUp(() {
    checked = [];
    keyAnswer = null;
  });
  Future<Refusal?> refusal(String text, {String? address}) async {
    try {
      await read(text, address: address);
      return null;
    } on RefusedCode catch (e) {
      return e.reason;
    }
  }

  test("reads the Monero GUI's View Only Wallet code", () async {
    expect(await read(gui(mainnet)), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 1234,
    ));
    expect(checked, [mainnet]);
    expect((await read(gui(stagenet))).address, stagenet);
    // Cake Wallet's spelling, and a scheme a QR reader gave in capitals.
    expect(await read('monero_wallet:$mainnet?view_key=$zeros&height=0'), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 0,
    ));
    expect(await read(' MONERO-WALLET:$mainnet?height=7&view_key=$zeros\n'), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 7,
    ));
  });

  test("reads Feather's View-Only QR and ignores the wallet's name", () async {
    expect(await read(feather({})), (
      address: mainnet,
      viewKey: zeros,
      restoreHeight: 1234,
    ));
    expect((await read(feather({'restoreHeight': '99'}))).restoreHeight, 99);
    expect((await read(feather({'walletName': words(5)}))).address, mainnet);
    expect(
      (await read(feather({'primaryAddress': stagenet}))).address,
      stagenet,
    );
  });

  test(
    'refuses whole anything with a spend key or seed, before reading it',
    () async {
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
        // A seed as a UR code, in one code or animated: the type says it.
        'ur:crypto-seed/${'ae' * 20}',
        'UR:CRYPTO-SEED/1-3/${'ae' * 20}',
      ]) {
        expect(await refusal(code), Refusal.spendKey, reason: code);
      }
      // Not even the view key check saw the address.
      expect(checked, isEmpty);
    },
  );

  test('refuses every other code', () async {
    for (final code in [
      '',
      'hello',
      words(11),
      // A payment request with a field it doesn't have, an animated key
      // images code, a link.
      'monero:$mainnet?amount=1.5',
      'monero:$mainnet?tx_amount=1&tx_amount=2',
      'monero:$mainnet?tx_amount',
      'monero:$mainnet?',
      'monero:',
      'ur:xmr-output/1-3/lpadaxcsencylobemohsgmoyadhdeynteelblrcygldwvarflojtcywlspdkfmzm',
      'ur:xmr-keyimage/${'ae' * 20}',
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
      // Integrated addresses, and no address at all.
      gui('4${'1' * 105}'),
      gui('5${'1' * 105}'),
      gui('4${'1' * 93}0'),
      gui(''),
      '4${'1' * 105}',
      'monero:4${'1' * 105}',
      // Hex that isn't 64 characters.
      '0' * 63,
      '0' * 65,
    ]) {
      expect(await refusal(code), Refusal.notWalletCode, reason: code);
    }
    expect(checked, isEmpty);
  });

  test('refuses a testnet wallet', () async {
    // Testnet's prefix starts an address with 9, or about one time in five
    // with A.
    expect(await refusal(gui('9${'1' * 94}')), Refusal.testnet);
    expect(await refusal(gui('A${'1' * 94}')), Refusal.testnet);
    expect(
      await refusal(feather({'primaryAddress': '9${'1' * 94}'})),
      Refusal.testnet,
    );
    expect(await refusal('9${'1' * 94}'), Refusal.testnet);
    // Its subaddresses start with B or C.
    expect(await refusal(gui('B${'1' * 94}')), Refusal.notWalletCode);
    expect(checked, isEmpty);
  });

  test('refuses a subaddress', () async {
    final mainnetSub = '8${'1' * 94}';
    final stagenetSub = '7${'1' * 94}';
    for (final code in [
      mainnetSub,
      stagenetSub,
      'monero:$mainnetSub?tx_amount=1',
      gui(mainnetSub),
      feather({'primaryAddress': stagenetSub}),
    ]) {
      expect(await refusal(code), Refusal.subaddress, reason: code);
    }
    expect(checked, isEmpty);
  });

  test('reads a primary address alone, as receive screens show it', () async {
    for (final (code, expected) in [
      (mainnet, mainnet),
      (' $stagenet\n', stagenet),
      ('monero:$mainnet', mainnet),
      ('MONERO:$stagenet', stagenet),
      (
        'monero:$mainnet?tx_amount=0.5&tx_description=Rent%20for%20May'
            '&recipient_name=Shop&tx_payment_id=${'0' * 64}',
        mainnet,
      ),
    ]) {
      expect(await read(code), (
        address: expected,
        viewKey: null,
        restoreHeight: null,
      ), reason: code);
    }
    // Nothing to check a key against.
    expect(checked, isEmpty);
  });

  test(
    "reads a private view key alone, checked against Setup's address",
    () async {
      expect(await read(zeros, address: mainnet), (
        address: null,
        viewKey: zeros,
        restoreHeight: null,
      ));
      expect(checked, [mainnet]);
      expect(
        (await read(' ${'A' * 64}\n', address: stagenet)).viewKey,
        'A' * 64,
      );

      // No address yet, or none that can be checked against.
      expect(await refusal(zeros), Refusal.needsAddress);
      expect(await refusal(zeros, address: ''), Refusal.needsAddress);
      expect(
        await refusal(zeros, address: '8${'1' * 94}'),
        Refusal.needsAddress,
      );
      expect(
        await refusal(zeros, address: '9${'1' * 94}'),
        Refusal.needsAddress,
      );
      expect(checked, [mainnet, stagenet]);
      keyAnswer = 'failed to parse address';
      expect(await refusal(zeros, address: mainnet), Refusal.needsAddress);

      // The spend key, a public key or another wallet's key.
      keyAnswer = 'view key does not match address';
      expect(await refusal(zeros, address: mainnet), Refusal.keyMismatch);
    },
  );

  test("refuses a key that isn't the address's view key", () async {
    keyAnswer = 'view key does not match address';
    expect(await refusal(gui(mainnet)), Refusal.keyMismatch);
    keyAnswer = 'failed to verify secret view key';
    expect(await refusal(feather({})), Refusal.keyMismatch);
    // An address with a wrong checksum.
    keyAnswer = 'failed to parse address';
    expect(await refusal(gui(mainnet)), Refusal.notWalletCode);
  });

  test("refuses a code when the view key check can't be made", () async {
    final refused = readWalletQr(
      gui(mainnet),
      keysProblem: ({required address, required viewKey}) async =>
          throw StateError('the wallet library would not load'),
    );
    await expectLater(
      refused,
      throwsA(
        isA<RefusedCode>().having((e) => e.reason, 'reason', Refusal.unchecked),
      ),
    );
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

    // The view key check runs on a helper isolate, which the fake clock of a
    // widget test doesn't wait for: let it finish, then settle the screens.
    Future<void> settleCheck(WidgetTester tester) async {
      final checking = find.text('Checking the code…');
      await tester.pump();
      for (var i = 0; i < 100 && checking.evaluate().isNotEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(checking, findsNothing);
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
      await settleCheck(tester);
      expect(find.text("This key isn't this address's view key"), findsOne);
      await tester.tap(find.text('Scan again'));
      await tester.pump();

      camera.show('https://example.com/');
      await tester.pump();
      expect(find.text('Not a wallet code'), findsOne);
      expect(find.text('Type it in instead'), findsOne);
      await tester.tap(find.text('Scan again'));
      await tester.pump();

      camera.show(guiCode(full));
      await tester.pump();
      // The camera is off while the key is checked off the UI isolate.
      expect(find.text('Checking the code…'), findsOne);
      expect(cameraView, findsNothing);
      await settleCheck(tester);
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
      await settleCheck(tester);
      expect(textIn(tester, address), mainnetFull.address());
      expect(textIn(tester, restoreHeight), '3100000');
      expect(find.text('Matches this address'), findsOne);
      expect(find.text('Filled from QR code'), findsOne);
    });

    testWidgets(
      'fills the address, then the view key, from codes of their own',
      (tester) async {
        final camera = useCamera();
        await phone(tester);
        await tester.pumpWidget(const MainApp());
        await tester.enterText(restoreHeight, '1500');
        await tester.pump();

        // A key before there is an address to check it against.
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        camera.show(full.secretViewKey());
        await tester.pump();
        expect(find.text('This key needs its address'), findsOne);
        await tester.tap(find.text('Scan again'));
        await tester.pump();

        // A subaddress, then the wallet's own receive code.
        camera.show(full.address(addressIndex: 1));
        await tester.pump();
        expect(find.text("That's a subaddress"), findsOne);
        await tester.tap(find.text('Scan again'));
        await tester.pump();
        camera.show('monero:${full.address()}?tx_amount=1');
        await tester.pumpAndSettle();
        expect(find.text('Watch a wallet'), findsOne);
        expect(textIn(tester, address), full.address());
        expect(textIn(tester, viewKey), isEmpty);
        expect(find.text('Address from QR code'), findsOne);

        // Its spend key and its public view key look like a view key, and
        // neither is one.
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        for (final key in [full.secretSpendKey(), full.publicViewKey()]) {
          camera.show(key);
          await settleCheck(tester);
          expect(find.text("This key isn't this address's view key"), findsOne);
          await tester.tap(find.text('Scan again'));
          await tester.pump();
        }

        camera.show(full.secretViewKey());
        await settleCheck(tester);
        expect(find.text('Watch a wallet'), findsOne);
        expect(textIn(tester, address), full.address());
        expect(textIn(tester, viewKey), full.secretViewKey());
        expect(textIn(tester, restoreHeight), '1500');
        expect(find.text('Filled from QR code'), findsOne);
        expect(find.text('Matches this address'), findsOne);
        expect(enabled(tester, 'Continue'), isTrue);

        // A typed key is no longer the scanned one.
        await tester.enterText(viewKey, mainnetFull.secretViewKey());
        await tester.pump();
        expect(find.text('Address from QR code'), findsOne);
      },
    );

    testWidgets('the iPhone camera hands each view its code, then stops it', (
      tester,
    ) async {
      // The Runner's side of the camera channel and of platform views,
      // played here: the app asks, and the "Runner" sends codes back.
      final messenger = tester.binding.defaultBinaryMessenger;
      final asked = <MethodCall>[];
      messenger.setMockMethodCallHandler(IosQrCamera.channel, (call) async {
        asked.add(call);
        return call.method == 'allowed' ? true : null;
      });
      Future<void> read(int view, String text) =>
          messenger.handlePlatformMessage(
            IosQrCamera.channel.name,
            IosQrCamera.channel.codec.encodeMethodCall(
              MethodCall('code', {'view': view, 'text': text}),
            ),
            (_) {},
          );
      final views = <int>[];
      // What the "Runner" does while it makes a view, before the app hears
      // that the view exists.
      Future<void> Function(int view)? making;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final view = (call.arguments as Map<Object?, Object?>)['id']! as int;
          views.add(view);
          await making?.call(view);
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(IosQrCamera.channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });
      final camera = IosQrCamera();
      qrCamera = camera;
      addTearDown(() => qrCamera = null);
      final spendCode = gui(
        mainnet,
        query: 'view_key=$zeros&height=1&spend_key=$zeros',
      );

      await phone(tester);
      await tester.pumpWidget(const MainApp());
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(asked.map((call) => call.method), ['allowed']);
      expect(views, hasLength(1));

      await read(views.first, 'https://example.com/');
      await tester.pump();
      expect(find.text('Not a wallet code'), findsOne);
      // The view went with the refusal, and its camera was told to stop.
      expect(find.byType(UiKitView), findsNothing);
      expect(
        asked.where((call) => call.method == 'stop').map((c) => c.arguments),
        [views.first],
      );
      // A code the view read as it went is dropped, not kept in memory.
      await read(views.first, spendCode);
      await tester.pump();
      expect(camera.heldCodes, 0);
      expect(find.text('Not a wallet code'), findsOne);

      // A code the next view reads before the app hears it was made is kept
      // for it.
      making = (view) => read(view, guiCode(full));
      await tester.tap(find.text('Scan again'));
      await tester.pump();
      await settleCheck(tester);
      expect(views, [views.first, views.first + 1]);
      expect(camera.heldCodes, 0);
      expect(find.text('Watch a wallet'), findsOne);
      expect(textIn(tester, address), full.address());
      expect(find.text('Filled from QR code'), findsOne);
      expect(
        asked.where((call) => call.method == 'stop').map((c) => c.arguments),
        [views.first, views.first + 1],
      );

      // A code read for a view that is taken away before the app hears it
      // was made is dropped when it goes.
      final made = Completer<void>();
      making = (view) async {
        await read(view, spendCode);
        await made.future;
      };
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(views, hasLength(3));
      expect(camera.heldCodes, 1);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(camera.heldCodes, 0);
      made.complete();
      await tester.pump();
      expect(find.text('Watch a wallet'), findsOne);
      expect(textIn(tester, address), full.address());
    });

    testWidgets(
      'the iPhone camera hands over an animated code part by part, and keeps '
      'the screen on when asked',
      (tester) async {
        final messenger = tester.binding.defaultBinaryMessenger;
        final asked = <MethodCall>[];
        messenger.setMockMethodCallHandler(IosQrCamera.channel, (call) async {
          asked.add(call);
          return null;
        });
        Future<void> read(int view, String text) =>
            messenger.handlePlatformMessage(
              IosQrCamera.channel.name,
              IosQrCamera.channel.codec.encodeMethodCall(
                MethodCall('code', {'view': view, 'text': text}),
              ),
              (_) {},
            );
        final made = <Map<Object?, Object?>>[];
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method == 'create') {
            final arguments = call.arguments as Map<Object?, Object?>;
            made.add(arguments);
            // The first part comes before the app hears the view was made.
            await read(arguments['id']! as int, 'part 1');
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(IosQrCamera.channel, null);
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
        });
        final camera = IosQrCamera();
        final parts = <String>[];

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: camera.view(parts.add, animated: true),
          ),
        );
        await tester.pump();
        expect(made, hasLength(1));
        // The Runner is told to keep reading.
        expect(
          const StandardMessageCodec().decodeMessage(
            ByteData.sublistView(made.single['params']! as Uint8List),
          ),
          {'animated': true},
        );
        final view = made.single['id']! as int;
        await read(view, 'part 2');
        await read(view, 'part 3');
        expect(parts, ['part 1', 'part 2', 'part 3']);
        expect(camera.heldCodes, 0);

        await camera.keepScreenOn(true);
        await camera.keepScreenOn(false);
        // Taking the view away stops its camera, and drops what it still
        // reads.
        await tester.pumpWidget(const SizedBox());
        await read(view, 'part 4');
        expect(parts, hasLength(3));
        expect(asked.map((call) => (call.method, call.arguments)), [
          ('keepScreenOn', true),
          ('keepScreenOn', false),
          ('stop', view),
        ]);
      },
    );

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
  Widget view(ValueChanged<String> onCode, {bool animated = false}) {
    _onCode = onCode;
    return const SizedBox.expand(key: Key('camera'));
  }

  @override
  Future<void> keepScreenOn(bool on) async {}

  void show(String code) => _onCode!(code);
}
