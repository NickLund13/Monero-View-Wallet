// Needs the native library: run `sh tool/fetch_monero_c.sh` first.
//
// Every wallet here is a random throwaway made when the test runs. No key is
// printed or written into this file. The tests of the saved wallet write it to
// a temporary folder, with its password in Windows Credential Manager under a
// name of its own (in memory on Linux), and delete both. Opening a saved
// wallet makes wallet2 open Monero's shared ring database, as the README
// explains: C:\ProgramData\.shared-ringdb\stagenet on Windows,
// ~/.shared-ringdb/stagenet on Linux.
//
// The tests that need a node are skipped unless MVW_STAGENET_NODE is set:
//   $env:MVW_STAGENET_NODE = "node.monerodevs.org:38089"; flutter test

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports
import 'package:monero/src/monero.dart';
import 'package:monero/src/wallet2.dart';
import 'package:monero_view_wallet/advanced_screen.dart';
import 'package:monero_view_wallet/home_screen.dart';
import 'package:monero_view_wallet/key_images_screen.dart';
import 'package:monero_view_wallet/lock.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/node_screen.dart';
import 'package:monero_view_wallet/pick_file.dart';
import 'package:monero_view_wallet/price.dart';
import 'package:monero_view_wallet/secret_store.dart';
import 'package:monero_view_wallet/session.dart';
import 'package:monero_view_wallet/settings_screen.dart';
import 'package:monero_view_wallet/setup_screen.dart';
import 'package:monero_view_wallet/tor.dart';
import 'package:monero_view_wallet/ui.dart';
import 'package:monero_view_wallet/wallet.dart';

import 'fake_check.dart';

void main() {
  final node = Platform.environment['MVW_STAGENET_NODE'];
  final needsNode = node == null ? 'set MVW_STAGENET_NODE=host:port' : false;
  final stagenetNode = publicNodes[Network.stagenet]!.first.host;
  late Wallet2WalletManager manager;

  // A throwaway wallet that can spend, standing in for the Monero GUI wallet,
  // and one on mainnet. Neither ever holds coins.
  late Wallet2Wallet full;
  late Wallet2Wallet mainnetFull;

  ViewWallet watch(Wallet2Wallet of, {int restoreHeight = 0}) =>
      ViewWallet.create(
        address: of.address(),
        viewKey: of.secretViewKey(),
        restoreHeight: restoreHeight,
      );

  // Saved in walletFile, as setup does.
  ViewWallet watchSaved(Wallet2Wallet of) => ViewWallet.create(
    address: of.address(),
    viewKey: of.secretViewKey(),
    restoreHeight: 1234,
    save: true,
  );

  final address = find.byKey(const Key('address'));
  final viewKey = find.byKey(const Key('viewKey'));
  final restoreHeight = find.byKey(const Key('restoreHeight'));
  String textIn(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;
  // Tall enough that no screen has to scroll.
  Future<void> phone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // Removing a wallet closes it on a helper isolate, which the fake clock of
  // a widget test doesn't wait for: let it finish, then settle the screens.
  Future<void> settleRemoving(WidgetTester tester) async {
    await tester.pump();
    final spinner = find.byType(CircularProgressIndicator);
    for (var i = 0; i < 100 && spinner.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  // Lets calls on the wallet's helper isolates finish, which the fake clock of
  // a widget test doesn't wait for either, until [done].
  Future<void> settleWallet(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(done(), isTrue);
  }

  bool shows(Finder finder) => finder.evaluate().isNotEmpty;

  bool enabled(WidgetTester tester, String button) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, button))
          .onPressed !=
      null;

  setUpAll(() {
    // Windows looks for DLLs in the current directory.
    Directory.current = 'windows/monero_c';
    // Credential Manager exists on Windows only. Elsewhere the saved wallets'
    // passwords are held in memory for the length of the run.
    if (!Platform.isWindows) secretStore = _MemoryStore();
    // Settings asks the node how fast it answers. In the tests no node
    // answers, and nothing is sent: a real request still running when the
    // tests end would crash the test process. The first-run test asks for
    // real.
    askNode = (_, {tor}) async => (height: 0, ms: 0);
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

  test('formats atomic units as XMR', () {
    expect(formatXmr(0), '0.0000');
    expect(formatXmr(1), '0.000000000001');
    expect(formatXmr(1500000000000), '1.5000');
    expect(formatXmr(123456789012345678), '123456.789012345678');
    expect(formatXmr(1999999999999, short: true), '1.9999');
    expect(formatXmr(1, short: true), '0.0000');
  });

  test('refuses anything that is not a view key, and names seed phrases', () {
    expect(viewKeyProblem('0' * 64), isNull);
    expect(viewKeyProblem('0' * 63), contains('64 characters'));
    expect(viewKeyProblem('g' * 64), contains('64 characters'));
    expect(viewKeyProblem('one two three'), contains('seed phrase'));
  });

  test('refuses anything that is not a primary address, and names secrets', () {
    expect(addressProblem(full.address()), isNull);
    expect(addressProblem(mainnetFull.address()), isNull);
    expect(addressProblem(''), contains('95 characters'));
    expect(addressProblem('one two three'), contains('seed phrase'));
    expect(addressProblem('0' * 64), contains('private key'));
    // Subaddresses start with 8 on mainnet and 7 on stagenet, testnet
    // addresses with 9.
    expect(addressProblem('8${'1' * 94}'), contains('subaddress'));
    expect(addressProblem('7${'1' * 94}'), contains('subaddress'));
    expect(addressProblem('9${'1' * 94}'), contains("isn't a primary address"));
  });

  test("tells the network from the address, and a node's from its height", () {
    expect(networkOf(full.address()), Network.stagenet);
    expect(networkOf(mainnetFull.address()), Network.mainnet);
    expect(networkOf('9${'1' * 94}'), isNull);
    // The same estimate as wallet2's own, give or take the blocks of the
    // seconds between the two.
    expect(
      approximateHeight(Network.mainnet),
      closeTo(mainnetFull.approximateBlockChainHeight(), 2),
    );
    expect(
      approximateHeight(Network.stagenet),
      closeTo(full.approximateBlockChainHeight(), 2),
    );
    final mainnetTip = approximateHeight(Network.mainnet);
    final stagenetTip = approximateHeight(Network.stagenet);
    expect(onNetwork(Network.mainnet, mainnetTip), isTrue);
    expect(onNetwork(Network.stagenet, stagenetTip), isTrue);
    expect(onNetwork(Network.mainnet, stagenetTip), isFalse);
    expect(onNetwork(Network.stagenet, mainnetTip), isFalse);
    // A node that answers nothing, or is years behind.
    expect(onNetwork(Network.mainnet, 0), isFalse);
    expect(onNetwork(Network.mainnet, mainnetTip - 600000), isFalse);
    // Ten years on, the two networks are still far apart.
    final later = DateTime.now().add(const Duration(days: 3650));
    expect(
      onNetwork(
        Network.stagenet,
        approximateHeight(Network.mainnet, later),
        later,
      ),
      isFalse,
    );
    expect(
      onNetwork(
        Network.mainnet,
        approximateHeight(Network.stagenet, later),
        later,
      ),
      isFalse,
    );
    expect(
      answerProblem(Network.mainnet, (height: mainnetTip, ms: 90)),
      isNull,
    );
    expect(
      answerProblem(Network.mainnet, (height: 0, ms: 90)),
      "can't reach it",
    );
    expect(
      answerProblem(Network.mainnet, (height: stagenetTip, ms: 90)),
      'not a mainnet node, or far from synced',
    );
  });

  test('accepts a node only as host:port, and no onion node without Tor', () {
    expect(nodeProblem('192.168.1.20:38081'), isNull);
    expect(nodeProblem('node.example.org:38089'), isNull);
    expect(nodeProblem('node.example.org'), contains('host:port'));
    expect(nodeProblem('http://node.example.org:38089'), contains('host:port'));
    expect(nodeProblem('node.example.org:99999'), contains('host:port'));
    expect(nodeProblem('user:pass@node.example.org:1'), contains('host:port'));
    expect(nodeProblem('${'a' * 56}.onion:38081'), isNull);
    // A name with the root's dot after it, or an empty label.
    expect(nodeProblem('node.example.org.:38089'), contains('host:port'));
    expect(nodeProblem('${'a' * 56}.onion.:38081'), contains('host:port'));
    expect(nodeProblem('.example.org:38089'), contains('host:port'));
    expect(nodeProblem('node..example.org:38089'), contains('host:port'));
  });

  test('checks a view key against its address', () async {
    String? problem(String address, String viewKey) =>
        ViewWallet.keysProblem(address: address, viewKey: viewKey);
    expect(problem(full.address(), full.secretViewKey()), isNull);
    expect(problem(full.address(), '0' * 64), contains('does not match'));
    expect(
      problem('5${'1' * 94}', full.secretViewKey()),
      'failed to parse address',
    );
    // On a helper isolate, as Scan wallet QR asks, again and again: the
    // wallet it checks with is freed each time, not left behind.
    final address = full.address();
    final key = full.secretViewKey();
    for (var i = 0; i < 3; i++) {
      expect(
        await Isolate.run(
          () => ViewWallet.keysProblem(address: address, viewKey: key),
        ),
        isNull,
      );
    }
  });

  testWidgets('a pasted seed phrase is refused and wiped at once', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(const MainApp());
    await tester.enterText(address, 'four five six');
    await tester.pump();
    expect(find.textContaining('seed phrase or a private key'), findsOne);
    expect(textIn(tester, address), isEmpty);

    await tester.enterText(viewKey, 'one two three');
    await tester.pump();
    expect(find.textContaining('That looks like a seed phrase.'), findsOne);
    expect(textIn(tester, viewKey), isEmpty);

    // A phrase whose words run together still can't be a view key.
    await tester.enterText(viewKey, 'word' * 25);
    await tester.pump();
    expect(textIn(tester, viewKey), isEmpty);
  });

  testWidgets('setup continues only when the view key matches the address', (
    tester,
  ) async {
    final other = manager.createWallet(
      path: '',
      password: '',
      networkType: Network.stagenet.id,
    );
    final otherKey = other.secretViewKey();
    manager.closeWallet(other, false);

    await phone(tester);
    await tester.pumpWidget(const MainApp());
    await tester.enterText(address, full.address());
    await tester.enterText(restoreHeight, '100');
    await tester.enterText(viewKey, '0' * 64);
    await tester.pump();
    expect(find.textContaining("doesn't belong to this address"), findsOne);
    expect(enabled(tester, 'Continue'), isFalse);
    expect(textIn(tester, viewKey), isEmpty);

    // Another wallet's key is what a pasted spend key looks like: a valid key
    // that isn't this address's view key. It is wiped too.
    await tester.enterText(viewKey, otherKey);
    await tester.pump();
    expect(find.textContaining("doesn't belong to this address"), findsOne);
    expect(textIn(tester, viewKey), isEmpty);

    await tester.enterText(viewKey, full.secretViewKey());
    await tester.pump();
    expect(find.text('Matches this address'), findsOne);
    expect(enabled(tester, 'Continue'), isTrue);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a node'), findsOne);
    expect(find.textContaining('one wallet'), findsOne);
    // Nothing is chosen yet, so nothing can be contacted.
    expect(enabled(tester, 'Start sync'), isFalse);
    await tester.tap(find.text(stagenetNode));
    await tester.pump();
    expect(enabled(tester, 'Start sync'), isTrue);

    // Going back forgets the wallet, and the key is no longer in the field.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(textIn(tester, viewKey), isEmpty);
    expect(enabled(tester, 'Continue'), isFalse);
  });

  testWidgets(
    'empties the clipboard after a paste, once the key is used or wiped',
    (tester) async {
      final clipboard = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await phone(tester);
      await tester.pumpWidget(const MainApp());
      // enterText puts the whole text in at once, as a paste does.
      await tester.enterText(address, full.address());
      await tester.enterText(restoreHeight, '100');
      await tester.pump();
      expect(clipboard, isEmpty, reason: 'the key is still to come');

      // Not this address's view key, so maybe the spend key: wiped, and off
      // the clipboard.
      await tester.enterText(viewKey, '0' * 64);
      await tester.pump();
      expect(textIn(tester, viewKey), isEmpty);
      expect(clipboard, ['']);

      await tester.enterText(viewKey, full.secretViewKey());
      await tester.pump();
      expect(clipboard, [''], reason: 'kept until the wallet is made');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(clipboard, ['', '']);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('refuses a restore height after the newest block', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(const MainApp());
    await tester.enterText(address, full.address());
    await tester.enterText(viewKey, full.secretViewKey());
    final tip = approximateHeight(Network.stagenet);
    await tester.enterText(restoreHeight, '${tip + 60000}');
    await tester.pump();
    expect(find.textContaining('after the newest block'), findsOne);
    expect(enabled(tester, 'Continue'), isFalse);

    await tester.enterText(restoreHeight, '${tip + 1000}');
    await tester.pump();
    expect(find.textContaining('after the newest block'), findsNothing);
    expect(enabled(tester, 'Continue'), isTrue);
  });

  test('creates a view-only wallet from address and view key', () {
    final wallet = watch(full);
    addTearDown(wallet.close);
    expect(wallet.isViewOnly, isTrue);
    expect(wallet.address, full.address());
    expect(wallet.balance, 0);
    expect(wallet.outputs, (total: 0, spent: 0, withoutKeyImage: 0));
    expect(wallet.transfers, isEmpty);
  });

  test('makes the subaddresses the full wallet has, and labels them', () {
    final wallet = watch(full);
    addTearDown(wallet.close);
    expect(wallet.subaddressCount, 1, reason: 'just the primary address');
    expect(wallet.subaddress(0), full.address());
    expect(wallet.addSubaddress(), 1);
    expect(wallet.addSubaddress(), 2);
    // The same keys give the same subaddress under the same number, as in
    // the Monero GUI.
    expect(wallet.subaddress(2), full.address(addressIndex: 2));
    expect(addressProblem(wallet.subaddress(2)), contains('subaddress'));

    wallet.setLabel(2, 'Rent from Alex');
    expect(wallet.label(2), 'Rent from Alex');
    expect(wallet.label(1), isEmpty);
  });

  test('rejects a view key that does not belong to the address', () {
    expect(
      () => ViewWallet.create(
        address: full.address(),
        viewKey: '0' * 64,
        restoreHeight: 0,
      ),
      throwsA(isA<WalletException>()),
    );
  });

  test('watches a mainnet wallet too', () {
    final wallet = watch(mainnetFull);
    addTearDown(wallet.close);
    expect(wallet.network, Network.mainnet);
    expect(wallet.isViewOnly, isTrue);
    expect(wallet.address, mainnetFull.address());
    final test = watch(full);
    addTearDown(test.close);
    expect(test.network, Network.stagenet);
    // A mainnet view key is checked against its address as on stagenet.
    expect(
      ViewWallet.keysProblem(
        address: mainnetFull.address(),
        viewKey: full.secretViewKey(),
      ),
      contains('does not match'),
    );
  });

  test(
    'imports key images from its own wallet, and explains other files',
    () async {
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final other = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.stagenet.id,
      );
      addTearDown(() => manager.closeWallet(other, false));
      final own = '${dir.path}/own_key_images';
      final foreign = '${dir.path}/foreign_key_images';
      final unrelated = '${dir.path}/unrelated';
      expect(full.exportKeyImages(own, all: true), isTrue);
      expect(other.exportKeyImages(foreign, all: true), isTrue);
      File(unrelated).writeAsStringSync('not a key images file');

      final wallet = watch(full);
      addTearDown(wallet.close);
      await wallet.importKeyImages(own);

      Future<ImportProblem?> problemWith(String path) async {
        try {
          await wallet.importKeyImages(path);
        } on WalletException catch (e) {
          return ImportProblem.from(e.message);
        }
        return null;
      }

      expect(await problemWith(foreign), ImportProblem.otherWallet);
      expect(await problemWith(unrelated), ImportProblem.notKeyImages);
      for (final (error, problem) in [
        (
          'The blockchain is out of date compared to the signed key images',
          ImportProblem.missingOutputs,
        ),
        ('Offset larger than known outputs', ImportProblem.missingOutputs),
        ('no connection to daemon', ImportProblem.noNode),
        ('error from is_key_image_spent call', ImportProblem.noNode),
        ('Signature check failed', ImportProblem.failed),
      ]) {
        expect(
          ImportProblem.from('Failed to import key images: $error'),
          problem,
          reason: error,
        );
      }

      // The size says how many key images a file holds: none in these, as
      // the throwaway wallets have no outputs.
      expect(keyImagesInFile(File(own).lengthSync()), 0);
      expect(keyImagesInFile(File(foreign).lengthSync()), 0);
      expect(keyImagesInFile(File(unrelated).lengthSync()), isNull);
      expect(keyImagesInFile(164 + 3 * 96), 3);
      expect(keyImagesInFile(164 + 3 * 96 + 1), isNull);
    },
  );

  test('reads only a key images export, by its header and size', () {
    final dir = Directory.systemTemp.createTempSync('mvw_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final own = '${dir.path}/own_key_images';
    expect(full.exportKeyImages(own, all: true), isTrue);
    expect(looksLikeKeyImagesFile(own), isTrue);

    final outputs = '${dir.path}/outputs';
    File(outputs).writeAsBytesSync([
      ...'Monero output export'.codeUnits,
      4,
      ...List.filled(100, 0),
    ]);
    expect(looksLikeKeyImagesFile(outputs), isFalse);
    expect(looksLikeKeyImagesFile('${dir.path}/missing'), isFalse);
    expect(looksLikeKeyImagesFile(dir.path), isFalse, reason: 'a folder');

    // The right header on a file far bigger than any export: refused before
    // wallet2 reads all of it into memory.
    final huge = '${dir.path}/huge';
    File(huge).openSync(mode: FileMode.write)
      ..writeFromSync(File(own).readAsBytesSync())
      ..truncateSync(maxKeyImagesFile + 1)
      ..closeSync();
    expect(looksLikeKeyImagesFile(huge), isFalse);
  });

  test('Remove wallet empties the ring database the app owns', () {
    final dir = Directory.systemTemp.createTempSync('mvw_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final rings = Directory('${dir.path}/rings');
    Directory('${rings.path}/stagenet').createSync(recursive: true);
    File('${rings.path}/data.mdb').writeAsStringSync('made up');
    File('${rings.path}/stagenet/data.mdb').writeAsStringSync('made up');
    walletFile = '${dir.path}${Platform.pathSeparator}wallet';
    ringDatabase = rings.path;
    addTearDown(() {
      walletFile = null;
      ringDatabase = null;
    });
    ViewWallet.forgetSaved();
    expect(rings.existsSync(), isTrue, reason: 'kept out of backups');
    expect(rings.listSync(), isEmpty);
  });

  test('says file sizes and addresses the short way', () {
    expect(formatSize(1), '1 byte');
    expect(formatSize(164), '164 bytes');
    expect(formatSize(1316), '1.3 KB');
    expect(formatSize(96164), '96 KB');
    expect(formatSize(2400000), '2.4 MB');
    expect(shortAddress('5${'0' * 94}9'), '500000…000009');
  });

  test('a rescan needs the node, and changes nothing without it', () async {
    final wallet = watch(full, restoreHeight: 1234);
    addTearDown(wallet.close);
    await expectLater(wallet.rescan(1000), throwsA(isA<WalletException>()));
    expect(wallet.restoreHeight, 1234);
    expect(wallet.remembered('mvw.restoreHeight'), isNull);
  });

  test(
    'the saved wallet keeps its lookahead and the height of its last rescan',
    () async {
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      walletFile = '${dir.path}${Platform.pathSeparator}wallet';
      addTearDown(() {
        ViewWallet.forgetSaved();
        walletFile = null;
        dir.deleteSync(recursive: true);
      });
      var wallet = ViewWallet.create(
        address: full.address(),
        viewKey: full.secretViewKey(),
        restoreHeight: 1234,
        save: true,
      );
      expect(wallet.lookahead, defaultLookahead);
      expect(
        () => wallet.setLookahead((accounts: 0, addresses: 200)),
        throwsArgumentError,
        reason: 'wallet2 would stop the app',
      );
      expect(
        () => wallet.setLookahead((accounts: 1 << 32, addresses: 1 << 32)),
        throwsArgumentError,
      );
      await wallet.setLookahead((accounts: 50, addresses: 300));
      expect(wallet.lookahead, (accounts: 50, addresses: 300));
      // What connect() and a rescan leave; both need a node.
      await wallet.save({
        'mvw.node': '127.0.0.1:9',
        'mvw.restoreHeight': '1000',
      });
      await wallet.close();

      wallet = ViewWallet.openSaved()!;
      expect(wallet.restoreHeight, 1000);
      expect(wallet.lookahead, (accounts: 50, addresses: 300));

      // Back to the default, and notes that can't be read are no notes.
      await wallet.setLookahead(defaultLookahead);
      expect(wallet.remembered('mvw.lookahead'), isNull);
      await wallet.save({'mvw.restoreHeight': 'not a height'});
      await wallet.close();
      wallet = ViewWallet.openSaved()!;
      addTearDown(wallet.close);
      expect(wallet.restoreHeight, 1234, reason: 'from the keys file');
      expect(wallet.lookahead, defaultLookahead);
    },
  );

  test('an unreachable node tests as unreachable', () async {
    // Nothing listens on this port of this computer.
    expect((await ViewWallet.probeNode('127.0.0.1:9')).height, 0);
  });

  // Probes take turns. A widget test that ends during one (Settings asks the
  // node when it opens) never runs its fake clock again, and that must not
  // keep the next probe waiting for its turn.
  testWidgets('a probe left behind by a finished widget test', (tester) async {
    ViewWallet.probeNode('127.0.0.1:9').ignore();
    await tester.pumpWidget(const SizedBox());
  });

  test('does not hold up the next probe', () async {
    final next = ViewWallet.probeNode('127.0.0.1:9');
    expect((await next.timeout(const Duration(seconds: 20))).height, 0);
  });

  group('Tor', () {
    // Stands in for Tor's proxy on this computer: notes what the wallet
    // library asks it for, and refuses.
    late ServerSocket proxy;
    late String tor;
    final asked = <List<int>>[];
    setUp(() async {
      proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      tor = '127.0.0.1:${proxy.port}';
      asked.clear();
      proxy.listen((socket) {
        socket.listen((chunk) {
          asked.add(chunk);
          socket.add([0, 0x5b, 0, 0, 0, 0, 0, 0]); // SOCKS4: rejected
          socket.close();
        }, onError: (_) {});
      });
    });
    tearDown(() async {
      await proxy.close();
      torProxy = null;
    });

    test('the wallet library hands an onion node to Tor by name', () async {
      final onion = '${'a' * 56}.onion'; // made up
      expect((await ViewWallet.probeNode('$onion:38081', tor: tor)).height, 0);
      // SOCKS4a: version 4, connect, the port, then 0.0.0.1, which says a name
      // follows for the proxy to look up.
      expect(asked.first.sublist(0, 8), [
        4,
        1,
        38081 >> 8,
        38081 & 255,
        0,
        0,
        0,
        1,
      ]);
      expect(latin1.decode(asked.first), contains(onion));

      // The next test without Tor is direct again.
      asked.clear();
      expect((await ViewWallet.probeNode('127.0.0.1:9')).height, 0);
      expect(asked, isEmpty);
    });

    test('a wallet told to use Tor never asks its node directly', () async {
      // Stands in for the node, and counts who connects to it.
      final node = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(node.close);
      var callers = 0;
      node.listen((socket) {
        callers++;
        socket.destroy();
      });
      final wallet = watch(full);
      addTearDown(wallet.close);

      await expectLater(
        wallet.connect('127.0.0.1:${node.port}', tor: tor),
        throwsA(
          isA<WalletException>().having(
            (e) => e.message,
            'message',
            "Can't reach the node over Tor.",
          ),
        ),
      );
      expect(asked, isNotEmpty, reason: 'Tor was asked for the node');
      expect(callers, 0);
      expect(wallet.tor, isNull);
      expect(torProxy, isNull);
    });

    test(
      "reaches the stagenet node and Kraken through the app's own Tor",
      () async {
        final dir = Directory.systemTemp.createTempSync('mvw_tor');
        // From windows/monero_c, where setUpAll leaves these tests.
        torProgram = File('../tor/tor${Platform.isWindows ? '.exe' : ''}')
            .absolute
            .path;
        torFolder = dir.path;
        addTearDown(() async {
          builtInTor.stop();
          torProgram = torFolder = null;
          // Tor lets go of its files a moment after it is told to stop.
          await Future<void>.delayed(const Duration(seconds: 2));
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Left in the temporary folder.
          }
        });

        // Tor has no time limit of its own. Say how far it got if it stalls.
        final tor = await builtInTor.start().timeout(
          const Duration(minutes: 3),
          onTimeout: () => fail(
            'Tor got to ${builtInTor.progress}% in 3 minutes. '
            'Its last lines:\n${builtInTor.notices.join('\n')}',
          ),
        );
        expect(tor, torAddress);
        expect(builtInTor.ready, isTrue);
        expect(
          (await ViewWallet.probeNode(node!, tor: tor)).height,
          greaterThan(0),
        );
        final wallet = watch(full);
        // Closing waits for the sync thread, which may be in the middle of a
        // request over Tor. The tests after this one needn't wait for it.
        addTearDown(
          () => wallet.close().timeout(
            const Duration(seconds: 10),
            onTimeout: () {},
          ),
        );
        expect(await wallet.connect(node, tor: tor), greaterThan(0));
        expect(wallet.tor, tor);
        expect(torProxy, tor);
        // Not only the first request: the scan moves too, over Tor.
        final scanFrom = wallet.height;
        final scanning = Stopwatch()..start();
        while (wallet.height <= scanFrom &&
            scanning.elapsed < const Duration(minutes: 2)) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          wallet.height,
          greaterThan(scanFrom),
          reason: 'no block scanned over Tor in 2 minutes',
        );
        final price = await HttpOverrides.runWithHttpOverrides(
          fetchXmrUsd,
          _NoOverrides(),
        );
        expect(price, greaterThan(0));
      },
      skip: needsNode,
      timeout: const Timeout(Duration(minutes: 8)),
    );

    test(
      'the Tor inside the app, as on iPhone, reaches the node, stops and '
      'starts again',
      () async {
        // The same tor, run here as a program with the command line the
        // iPhone build gives the library, and driven the same way.
        final program = File('../tor/tor${Platform.isWindows ? '.exe' : ''}')
            .absolute
            .path;
        final dir = Directory.systemTemp.createTempSync('mvw_tor');
        final realRun = runTorInApp;
        Process? process;
        var runs = 0;
        runTorInApp = (arguments) async {
          if (runs++ > 0) return 'running';
          process = await Process.start(
            program,
            arguments,
            environment: Platform.isLinux
                ? {'LD_LIBRARY_PATH': File(program).parent.path}
                : null,
          );
          process!.stdout.drain<void>();
          process!.stderr.drain<void>();
          return 'started';
        };
        torInApp = true;
        torFolder = dir.path;
        final tor = builtInTor = BuiltInTor();
        addTearDown(() async {
          tor.stop();
          builtInTor = BuiltInTor();
          runTorInApp = realRun;
          torInApp = false;
          torFolder = null;
          process?.kill();
          await process?.exitCode;
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Left in the temporary folder.
          }
        });

        Future<String> connect() => tor.start().timeout(
          const Duration(minutes: 3),
          onTimeout: () => fail(
            'Tor got to ${tor.progress}% in 3 minutes. '
            'It last said:\n${tor.notices.join('\n')}',
          ),
        );
        final proxy = await connect();
        expect(
          (await ViewWallet.probeNode(node!, tor: proxy)).height,
          greaterThan(0),
        );

        // Off the network: nothing goes through it any more.
        tor.stop();
        final colon = proxy.lastIndexOf(':');
        Future<bool> listening() async {
          try {
            (await Socket.connect(
              proxy.substring(0, colon),
              int.parse(proxy.substring(colon + 1)),
            )).destroy();
            return true;
          } on SocketException {
            return false;
          }
        }

        for (var i = 0; i < 50 && await listening(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(await listening(), isFalse);

        // Started again: the same Tor, back on the network.
        expect(await connect(), proxy);
        expect(runs, 1, reason: 'the same Tor, not a second one');
        expect(
          (await ViewWallet.probeNode(node, tor: proxy)).height,
          greaterThan(0),
        );
      },
      skip: needsNode,
      timeout: const Timeout(Duration(minutes: 8)),
    );

    testWidgets("an onion node is only used over the app's own Tor", (
      tester,
    ) async {
      final real = builtInTor;
      final fake = builtInTor = _FakeTor();
      torProgram = 'tor'; // this build has one
      addTearDown(() {
        builtInTor = real;
        torProgram = null;
      });
      final chosen = <(String, String?)>[];
      await phone(tester);
      await tester.pumpWidget(
        MainApp(
          home: NodeScreen(
            network: Network.stagenet,
            action: 'Save',
            onChosen: (node, tor, _) async => chosen.add((node, tor)),
          ),
        ),
      );
      Switch overTor() => tester.widget<Switch>(find.byType(Switch));
      expect(overTor().value, isFalse);
      expect(find.text('TOR (EXPERIMENTAL)'), findsOne);
      expect(find.textContaining("don't rely on it yet"), findsOne);

      final onion = '${'a' * 56}.onion:38081'; // made up
      await tester.enterText(find.byKey(const Key('ownNode')), onion);
      await tester.pump();
      expect(overTor().value, isTrue);
      expect(overTor().onChanged, isNull, reason: "it can't be turned off");

      // Tor doesn't start: the node is not connected to.
      fake.failure = 'Tor stopped before it connected.';
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Tor stopped before it connected.'), findsOne);
      expect(chosen, isEmpty);

      fake.failure = null;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Tor stopped before it connected.'), findsNothing);
      expect(chosen, [(onion, torAddress)]);

      // Any other node goes over Tor only when the switch is on.
      chosen.clear();
      const lan = '192.168.1.20:38081';
      await tester.enterText(find.byKey(const Key('ownNode')), lan);
      await tester.pump();
      expect(overTor().value, isFalse);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect over Tor'));
      await tester.pump();
      expect(overTor().value, isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(chosen, [(lan, null), (lan, torAddress)]);

      // Leaving with no wallet on Tor stops the Tor that was started.
      expect(fake.stops, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(fake.stops, 1);
    });

    testWidgets('Test asks an onion node over Tor, whichever node is picked', (
      tester,
    ) async {
      final real = builtInTor;
      builtInTor = _FakeTor();
      torProgram = 'tor'; // this build has one
      final fake = askNode;
      final asked = <(String, String?)>[];
      askNode = (node, {tor}) async {
        asked.add((node, tor));
        return (height: 0, ms: 0);
      };
      addTearDown(() {
        builtInTor = real;
        torProgram = null;
        askNode = fake;
      });
      await phone(tester);
      await tester.pumpWidget(
        MainApp(
          home: NodeScreen(
            network: Network.stagenet,
            action: 'Save',
            onChosen: (_, _, _) async {},
          ),
        ),
      );
      final onion = '${'a' * 56}.onion:38081'; // made up
      await tester.enterText(find.byKey(const Key('ownNode')), onion);
      await tester.pump();
      // A clearnet public node is picked with Tor off, and the own node's
      // onion address is still in its field, so its Test button still works.
      await tester.tap(find.text(stagenetNode));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();
      expect(asked, [(onion, torAddress)]);
      expect(find.text("Can't reach this node over Tor."), findsOne);
    });

    testWidgets('Test goes over Tor while the switch shows Tor on', (
      tester,
    ) async {
      final real = builtInTor;
      builtInTor = _FakeTor();
      torProgram = 'tor'; // this build has one
      final fake = askNode;
      final asked = <(String, String?)>[];
      askNode = (node, {tor}) async {
        asked.add((node, tor));
        return (height: 0, ms: 0);
      };
      addTearDown(() {
        builtInTor = real;
        torProgram = null;
        askNode = fake;
      });
      await phone(tester);
      final onion = '${'c' * 56}.onion:38089'; // made up
      await tester.pumpWidget(
        MainApp(
          home: NodeScreen(
            network: Network.stagenet,
            action: 'Save',
            added: [onion],
            onChosen: (_, _, _) async {},
          ),
        ),
      );
      const lan = '192.168.1.20:38081';
      await tester.enterText(find.byKey(const Key('ownNode')), lan);
      await tester.pump();
      // An onion public node is picked: the switch reads on and is locked,
      // and the own node's Test button still works.
      await tester.ensureVisible(find.text(onion));
      await tester.tap(find.text(onion));
      await tester.pump();
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      await tester.ensureVisible(find.text('Test'));
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();
      expect(asked, [(lan, torAddress)]);
      expect(find.text("Can't reach this node over Tor."), findsOne);
    });

    testWidgets('Home says how far Tor is, and when it could not start', (
      tester,
    ) async {
      final real = builtInTor;
      final fake = builtInTor = _FakeTor();
      addTearDown(() => builtInTor = real);
      final session = _OnNode(watch(full), stagenetNode, tor: torAddress)
        ..synced = true
        ..scanned = true;
      await phone(tester);
      await tester.pumpWidget(MainApp(home: HomeScreen(session)));
      expect(find.text('Connecting to Tor… 0%'), findsOne);

      fake
        ..progress = 45
        ..notifyListeners();
      await tester.pump();
      expect(find.text('Connecting to Tor… 45%'), findsOne);

      fake
        ..error = 'Tor stopped before it connected.'
        ..notifyListeners();
      await tester.pump();
      expect(
        find.text(
          'Tor stopped before it connected. '
          "Your node can't be reached without Tor.",
        ),
        findsOne,
      );

      fake
        ..progress = 100
        ..error = null
        ..notifyListeners();
      await tester.pump();
      expect(find.textContaining('Tor'), findsNothing);

      // Taking the screen away closes the wallet.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the USD question says Kraken is asked over Tor', (
      tester,
    ) async {
      final real = builtInTor;
      builtInTor = _FakeTor()..progress = 100;
      addTearDown(() => builtInTor = real);
      final session = _OnNode(watch(full), stagenetNode, tor: torAddress)
        ..synced = true
        ..scanned = true
        ..height = 2000
        ..nodeHeight = 2000
        ..balance = 2500000000000
        ..unlocked = 1500000000000;
      await phone(tester);
      await tester.pumpWidget(MainApp(home: HomeScreen(session)));
      await tester.tap(find.textContaining('2.5000'));
      await tester.pumpAndSettle();
      expect(find.textContaining('over Tor like your node'), findsOne);
      expect(find.textContaining('IP address'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(usdPrice.on, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the first scan says whether Tor is connected', (tester) async {
      final real = builtInTor;
      final fake = builtInTor = _FakeTor();
      addTearDown(() => builtInTor = real);
      await phone(tester);
      await tester.pumpWidget(
        MainApp(
          home: HomeScreen(_OnNode(watch(full), stagenetNode, tor: torAddress)),
        ),
      );
      expect(find.text('Scanning the blockchain'), findsOne);
      expect(find.text('Connecting… 0%'), findsOne);
      fake
        ..progress = 100
        ..notifyListeners();
      await tester.pump();
      expect(find.text('Connected'), findsOne);
      fake
        ..progress = 0
        ..error = 'Tor stopped before it connected.'
        ..notifyListeners();
      await tester.pump();
      expect(find.text('Not running'), findsOne);

      // Without Tor the row is not there.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MainApp(home: HomeScreen(_OnNode(watch(full), stagenetNode))),
      );
      expect(find.text('Tor'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a build without Tor says so and leaves the switch off', (
      tester,
    ) async {
      await phone(tester);
      await tester.pumpWidget(
        MainApp(
          home: NodeScreen(
            network: Network.stagenet,
            action: 'Save',
            onChosen: (_, _, _) async {},
          ),
        ),
      );
      expect(find.text('This build has no Tor yet.'), findsOne);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });
  });

  testWidgets("Choose a node offers the public nodes of the wallet's network", (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(
      MainApp(
        home: NodeScreen(
          network: Network.mainnet,
          action: 'Start sync',
          onChosen: (_, _, _) async {},
        ),
      ),
    );
    expect(find.text('PUBLIC NODES'), findsOne);
    expect(find.text(publicNodes[Network.mainnet]!.first.host), findsOne);
    expect(find.text(stagenetNode), findsNothing);
    expect(find.text('192.168.1.20:18081'), findsOne, reason: 'the hint');
    // The privacy note stays.
    expect(find.textContaining('one wallet'), findsOne);

    // Picking an onion node turns Tor on, and it can't be turned off.
    final onion = publicNodes[Network.mainnet]!.firstWhere(
      (n) => isOnion(n.host),
    );
    await tester.ensureVisible(find.text(onion.host));
    await tester.tap(find.text(onion.host));
    await tester.pump();
    final overTor = tester.widget<Switch>(find.byType(Switch));
    expect(overTor.value, isTrue);
    expect(overTor.onChanged, isNull);
  });

  testWidgets('a public node can be added to the list, and is kept', (
    tester,
  ) async {
    final chosen = <(String, List<String>)>[];
    await phone(tester);
    await tester.pumpWidget(
      MainApp(
        home: NodeScreen(
          network: Network.stagenet,
          action: 'Save',
          current: 'old.example:38089',
          added: const ['old.example:38089'],
          onChosen: (node, _, added) async => chosen.add((node, added)),
        ),
      ),
    );
    expect(find.text('Added by you'), findsOne);

    // The node in use is the one picked.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(chosen.single.$1, 'old.example:38089');

    await tester.tap(find.text('Add another node'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addNode')), 'new.example');
    await tester.pump();
    expect(find.textContaining('host:port'), findsOne);
    expect(enabled(tester, 'Add'), isFalse);
    await tester.enterText(
      find.byKey(const Key('addNode')),
      'new.example:38089',
    );
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('new.example:38089'), findsOne);
    expect(find.text('Added by you'), findsNWidgets(2));

    // The node just added is picked, and both are kept.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(chosen.last.$1, 'new.example:38089');
    expect(chosen.last.$2, ['old.example:38089', 'new.example:38089']);

    await tester.tap(find.byTooltip('Remove from the list').first);
    await tester.pump();
    expect(find.text('old.example:38089'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(chosen.last.$2, ['new.example:38089']);

    // Removing the one picked leaves nothing picked.
    await tester.tap(find.byTooltip('Remove from the list'));
    await tester.pump();
    expect(enabled(tester, 'Save'), isFalse);
  });

  testWidgets('Test speed asks each public node how fast it answers, or only '
      'the one picked', (tester) async {
    final real = askNode;
    final realTor = builtInTor;
    builtInTor = _FakeTor();
    torProgram = 'tor'; // this build has one
    addTearDown(() {
      askNode = real;
      builtInTor = realTor;
      torProgram = null;
    });
    final tip = approximateHeight(Network.stagenet);
    final hosts = [for (final n in publicNodes[Network.stagenet]!) n.host];
    const mainnetNode = 'mainnet.example:18089';
    final onion = '${'b' * 56}.onion:38089'; // made up
    final answers = {
      hosts[0]: (height: tip, ms: 120),
      hosts[1]: (height: tip - 10, ms: 80),
      hosts[2]: (height: 0, ms: 15000),
      mainnetNode: (height: approximateHeight(Network.mainnet), ms: 50),
      onion: (height: tip, ms: 900),
    };
    final asked = <(String, String?)>[];
    askNode = (node, {tor}) async {
      asked.add((node, tor));
      return answers[node]!;
    };
    await phone(tester);
    Future<void> show({required bool testAll}) => tester.pumpWidget(
      MainApp(
        home: NodeScreen(
          key: ValueKey(testAll),
          network: Network.stagenet,
          action: 'Save',
          added: [mainnetNode, onion],
          testAll: testAll,
          onChosen: (_, _, _) async {},
        ),
      ),
    );

    // Every node, the default.
    await show(testAll: true);
    expect(asked, isEmpty, reason: 'nothing is asked before Test speed');
    await tester.tap(find.text('Test speed'));
    await tester.pumpAndSettle();
    // Without Tor, an onion node isn't asked.
    expect(asked, [
      for (final node in answers.keys)
        if (node != onion) (node, null),
    ]);
    expect(
      find.text(
        'Run by ${publicNodes[Network.stagenet]![0].operator} · 120 ms',
      ),
      findsOne,
    );
    expect(find.textContaining('10 blocks behind'), findsOne);
    expect(find.textContaining("can't reach it"), findsOne);
    expect(
      find.text('Added by you · not a stagenet node, or far from synced'),
      findsOne,
    );
    // With Tor on, every node is asked through it.
    asked.clear();
    await tester.tap(find.text('Connect over Tor'));
    await tester.pump();
    await tester.tap(find.text('Test speed'));
    await tester.pumpAndSettle();
    expect(asked, [for (final node in answers.keys) (node, torAddress)]);
    expect(find.text('Added by you · 900 ms'), findsOne);

    // Only the node picked, when Settings says so.
    asked.clear();
    await show(testAll: false);
    expect(enabled(tester, 'Test speed'), isFalse, reason: 'nothing picked');
    Future<void> testSpeed(String node) async {
      await tester.tap(find.text(node));
      await tester.pump();
      await tester.tap(find.text('Test speed'));
      await tester.pumpAndSettle();
    }

    await testSpeed(hosts[0]);
    await testSpeed(hosts[1]);
    expect(asked, [(hosts[0], null), (hosts[1], null)]);
    // Answers stay on their rows, so nodes can be compared one by one.
    expect(find.textContaining('120 ms'), findsOne);
    expect(find.textContaining('10 blocks behind'), findsOne);
    // An onion node is always asked over Tor.
    await testSpeed(onion);
    expect(asked.last, (onion, torAddress));
  });

  test('tells synced from catching up, and when to show the notice', () {
    final session = WalletSession(watch(full));
    addTearDown(session.dispose);

    session
      ..height = 100
      ..nodeHeight = 101;
    expect(session.catchingUp, isTrue, reason: 'first scan not finished');
    session.synced = true;
    expect(session.catchingUp, isFalse, reason: 'one block behind is normal');
    session.nodeHeight = 105;
    expect(session.catchingUp, isTrue);
    expect(session.blocksToGo, 5);

    session
      ..balance = 3
      ..unlocked = 1
      ..transfers = [
        Transfer(
          incoming: true,
          amount: 2,
          height: 97,
          confirmations: 4,
          time: DateTime(2026),
        ),
      ];
    expect(session.locking, 2);
    expect(session.lockingBlocks, 6);

    expect(session.showKeyImagesNotice, isFalse);
    session.outputs = (total: 2, spent: 0, withoutKeyImage: 2);
    expect(session.showKeyImagesNotice, isTrue);
    session.dismissKeyImagesNotice();
    expect(session.showKeyImagesNotice, isFalse);
    session.outputs = (total: 3, spent: 0, withoutKeyImage: 3);
    expect(session.showKeyImagesNotice, isTrue, reason: 'a new output came');
  });

  test('offers the newest unpaid subaddress, within what the GUI watches', () {
    final session = WalletSession(watch(full));
    addTearDown(session.dispose);
    Transfer paidTo(int subaddress) => Transfer(
      incoming: true,
      amount: 1,
      height: 100,
      confirmations: 1,
      time: DateTime(2026),
      subaddresses: {subaddress},
    );

    expect(session.freshSubaddress(), 1, reason: 'never the primary address');
    expect(session.freshSubaddress(), 1, reason: 'nobody has paid it yet');
    session.transfers = [paidTo(1)];
    expect(session.paidSubaddresses, {1});
    expect(session.freshSubaddress(), 2);

    // Within 50 of the highest one paid: up to #50 here.
    while (session.canAddSubaddress) {
      session.wallet.addSubaddress();
    }
    expect(session.wallet.subaddressCount - 1, 1 + receiveAhead - 1);
    session.transfers = [paidTo(1), paidTo(20)];
    expect(session.canAddSubaddress, isTrue);
  });

  testWidgets('Home keeps the last balance and says so when the node is gone', (
    tester,
  ) async {
    final session = WalletSession(watch(full))
      ..synced = true
      ..scanned = true
      ..height = 2000
      ..nodeHeight = 2000
      ..balance = 2500000000000
      ..unlocked = 1500000000000
      ..outputs = (total: 3, spent: 1, withoutKeyImage: 2)
      ..transfers = [
        Transfer(
          incoming: true,
          amount: 1000000000000,
          height: 1997,
          confirmations: 4,
          time: DateTime(2026, 10, 8),
        ),
        Transfer(
          incoming: false,
          amount: 500000000000,
          height: 1500,
          confirmations: 501,
          time: DateTime(2026, 10, 1),
        ),
      ];
    await phone(tester);
    await tester.pumpWidget(
      MaterialApp(theme: darkTheme, home: HomeScreen(session)),
    );
    expect(find.textContaining('2.5000'), findsOne);
    expect(find.text('1.5000 unlocked · 1.0000 locking (6 blocks)'), findsOne);
    expect(find.textContaining('Synced to block 2000'), findsOne);
    expect(find.text('4 of 10 confirmations'), findsOne);
    expect(find.text('1 Oct 2026 · found via key images'), findsOne);
    expect(find.textContaining('2 outputs without key images'), findsOne);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Key images not imported yet'), findsOne);

    session.reachable = false;
    session.dismissKeyImagesNotice(); // any change redraws the screen
    await tester.pump();
    expect(find.textContaining("Can't reach your node"), findsOne);
    expect(find.text('Change node'), findsOne);
    expect(find.textContaining('2.5000'), findsOne);

    // Taking the screen away closes the wallet.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Home saves the wallet when the app loses focus', (tester) async {
    // On an iPhone this comes before the app goes to the background, where
    // the system can end it without warning.
    final session = _CountingSaves(watch(full))
      ..synced = true
      ..scanned = true;
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(session.saves, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(session.saves, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Receive shows a new subaddress to copy, share and label', (
    tester,
  ) async {
    final session = WalletSession(watch(full))
      ..synced = true
      ..scanned = true;
    final wallet = session.wallet;
    String? clipboard;
    final shared = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Share.invoke') shared.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    Future<void> openReceive() async {
      await tester.tap(find.byTooltip('Receive'));
      await tester.pumpAndSettle();
    }

    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    await openReceive();
    expect(find.text('Subaddress #1'), findsOne);
    expect(find.text('New · not used yet'), findsOne);
    expect(find.text(full.address(addressIndex: 1)), findsOne);
    expect(find.bySemanticsLabel('QR code of the subaddress'), findsOne);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(clipboard, full.address(addressIndex: 1));
    expect(find.text('Copied'), findsOne);
    // Tests run as Android, which has a share sheet.
    await tester.tap(find.text('Share'));
    expect(shared, [full.address(addressIndex: 1)]);

    // A seed pasted as a label is refused, and never kept in the wallet.
    final label = find.byKey(const Key('label'));
    await tester.enterText(label, List.filled(12, 'fake').join(' '));
    await tester.pump();
    expect(find.textContaining('so it was left out'), findsOne);
    expect(textIn(tester, label), isEmpty);
    expect(wallet.label(1), isEmpty);

    await tester.enterText(label, 'Rent from Alex');
    await tester.pump();
    expect(find.textContaining('so it was left out'), findsNothing);
    expect(wallet.label(1), 'Rent from Alex');

    await tester.tap(find.text('New'));
    await tester.pump();
    expect(find.text('Subaddress #2'), findsOne);
    expect(find.text(full.address(addressIndex: 2)), findsOne);
    expect(find.text('Copy'), findsOne);
    expect(textIn(tester, find.byKey(const Key('label'))), isEmpty);
    expect(wallet.label(1), 'Rent from Alex', reason: 'kept with #1');

    // Coming back shows the same one until somebody pays it.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await openReceive();
    expect(find.text('Subaddress #2'), findsOne);
    session.transfers = [
      Transfer(
        incoming: true,
        amount: 1,
        height: 0,
        confirmations: 0,
        time: DateTime(2026),
        subaddresses: {2},
      ),
    ];
    session.dismissKeyImagesNotice(); // any change redraws the screen
    await tester.pump();
    expect(find.text('Paid already · tap New for the next payer'), findsOne);

    // No further than the GUI watches.
    while (session.canAddSubaddress) {
      wallet.addSubaddress();
    }
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await openReceive();
    expect(find.text('Subaddress #${2 + receiveAhead - 1}'), findsOne);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'New'))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('No more new ones for now'), findsOne);

    // The Windows test build has no share sheet.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    session.dismissKeyImagesNotice();
    await tester.pump();
    expect(find.text('Share'), findsNothing);
    expect(find.text('Copy'), findsOne);
    debugDefaultTargetPlatformOverride = null;

    // Taking the screens away closes the wallet.
    await tester.pumpWidget(const SizedBox());
  });

  group('a key images file opened with the app', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mvw_test'));
    tearDown(() {
      receivedKeyImagesFile.value = null;
      dir.deleteSync(recursive: true);
    });

    /// What iOS hands over: the app's own copy, alone in a folder. Made up
    /// text, not key images.
    KeyImagesFile arrive(String name) {
      final folder = Directory('${dir.path}/$name')..createSync();
      final file = File('${folder.path}/$name')
        ..writeAsStringSync('made up: $name');
      return KeyImagesFile(file.path, copy: true);
    }

    bool exists(KeyImagesFile file) => File(file.path).existsSync();

    testWidgets('opens Import key images, imports when asked, and is deleted', (
      tester,
    ) async {
      final session = _RecordsImports(watch(full), 'node.example:38081')
        ..synced = true
        ..scanned = true;
      await phone(tester);
      // The file that started the app comes before Home.
      final first = arrive('first');
      offerKeyImagesFile(first);
      await tester.pumpWidget(
        MaterialApp(theme: darkTheme, home: HomeScreen(session)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Import key images'), findsOne);
      expect(find.text('first'), findsOne);
      expect(session.imported, isEmpty, reason: 'nothing without a tap');

      // A newer one replaces it on the open screen.
      final second = arrive('second');
      offerKeyImagesFile(second);
      await tester.pumpAndSettle();
      expect(exists(first), isFalse);
      expect(find.text('second'), findsOne);
      expect(find.text('Import key images'), findsOne, reason: 'not twice');

      await tester.tap(find.text('Import this file'));
      await tester.pumpAndSettle();
      expect(session.imported, ['made up: second']);
      expect(exists(second), isFalse);
      expect(Directory('${dir.path}/second').existsSync(), isFalse);
      expect(find.text('Import this file'), findsNothing);
      expect(find.text('Choose file'), findsOne);

      // One that is left without importing it is deleted too.
      final third = arrive('third');
      offerKeyImagesFile(third);
      await tester.pumpAndSettle();
      expect(find.text('third'), findsOne);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Import key images'), findsNothing);
      expect(exists(third), isFalse);
      expect(session.imported, hasLength(1));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('waits for the scan to catch up, then imports by itself', (
      tester,
    ) async {
      final session = _RecordsImports(watch(full), 'node.example:38081')
        ..height = 100
        ..nodeHeight = 150;
      await phone(tester);
      await tester.pumpWidget(
        MaterialApp(theme: darkTheme, home: HomeScreen(session)),
      );
      expect(find.text('Scanning the blockchain'), findsOne);
      final early = arrive('during the scan');
      offerKeyImagesFile(early);
      await tester.pumpAndSettle();
      expect(find.text('during the scan'), findsOne);
      expect(find.textContaining('An import waits for it'), findsOne);
      await tester.tap(find.text('Import this file'));
      await tester.pumpAndSettle();
      expect(find.text('Finishing sync first'), findsOne);
      expect(find.text('100'), findsOne, reason: 'scanned to');
      expect(find.text('150'), findsOne, reason: 'the node is at');
      expect(find.text('Syncing · 50 blocks to go'), findsOne);
      expect(find.text('Cancel import'), findsOne);
      expect(session.imported, isEmpty);

      session
        ..synced = true
        ..scanned = true
        ..height = 150;
      session.dismissKeyImagesNotice(); // any change redraws the screens
      await tester.pumpAndSettle();
      expect(session.imported, ['made up: during the scan']);
      expect(exists(early), isFalse);
      expect(find.text('Finishing sync first'), findsNothing);
      expect(find.text('Choose file'), findsOne);
      expect(find.text('Import key images'), findsOne, reason: 'not twice');

      // Cancel import gives the file up.
      session
        ..synced = false
        ..nodeHeight = 160;
      final cancelled = arrive('cancelled');
      offerKeyImagesFile(cancelled);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import this file'));
      await tester.pumpAndSettle();
      expect(find.text('Finishing sync first'), findsOne);
      await tester.tap(find.text('Cancel import'));
      await tester.pumpAndSettle();
      expect(find.text('Finishing sync first'), findsNothing);
      expect(exists(cancelled), isFalse);
      expect(session.imported, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without a wallet it is deleted at once, and setup says why', (
      tester,
    ) async {
      final early = arrive('early');
      offerKeyImagesFile(early);
      await tester.pumpWidget(const MainApp());
      await tester.pump();
      expect(exists(early), isFalse);
      expect(find.textContaining('Set up the wallet first'), findsOne);

      final later = arrive('later');
      offerKeyImagesFile(later);
      await tester.pump();
      expect(exists(later), isFalse);
      expect(receivedKeyImagesFile.value, isNull);
    });
  });

  group('Import problem', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mvw_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    late Future<KeyImagesFile?> Function() dialog;
    setUp(() => dialog = pickKeyImagesFile);
    tearDown(() => pickKeyImagesFile = dialog);

    testWidgets("says when a file is another wallet's, and takes another", (
      tester,
    ) async {
      final other = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.stagenet.id,
      );
      addTearDown(() => manager.closeWallet(other, false));
      // As the iPhone keeps them: copies, each alone in a folder.
      KeyImagesFile export(Wallet2Wallet from, String name) {
        final folder = Directory('${dir.path}/$name')..createSync();
        expect(from.exportKeyImages('${folder.path}/$name', all: true), isTrue);
        return KeyImagesFile('${folder.path}/$name', copy: true);
      }

      final foreign = export(other, 'foreign');
      final own = export(full, 'own');
      final picks = [foreign, own];
      pickKeyImagesFile = () async => picks.removeAt(0);
      final session = _OnNode(watch(full), 'node.example:38081')
        ..synced = true
        ..scanned = true;
      addTearDown(session.dispose);
      await phone(tester);
      await tester.pumpWidget(
        MaterialApp(theme: darkTheme, home: KeyImagesScreen(session)),
      );

      await tester.tap(find.text('Choose file'));
      final otherWallet = find.text('This file is from another wallet');
      await settleWallet(tester, () => shows(otherWallet));
      expect(find.text('Wallet on this device'), findsOne);
      expect(find.text(shortAddress(full.address())), findsOne);
      expect(find.text('foreign (164 bytes)'), findsOne);

      await tester.tap(find.text('Choose another file'));
      // Deleted once the import is done.
      await settleWallet(tester, () => !File(own.path).existsSync());
      expect(find.text('LAST IMPORT'), findsOne);
      expect(otherWallet, findsNothing);
      expect(session.lastImport!.fileName, 'own');
      expect(File(foreign.path).existsSync(), isFalse);
    });

    testWidgets(
      'waits for the next block once, then says outputs are missing',
      (tester) async {
        // Made-up bytes, as many as a key images file with 3 key images has.
        final three = File('${dir.path}/three')
          ..writeAsBytesSync(List.filled(164 + 3 * 96, 0));
        pickKeyImagesFile = () async => KeyImagesFile(three.path);
        final session =
            _FailsImport(
                watch(full, restoreHeight: 1234),
                'node.example:38081',
                'Failed to import key images: The blockchain is out of date '
                    'compared to the signed key images',
              )
              ..synced = true
              ..scanned = true
              ..height = 2000
              ..nodeHeight = 2001
              ..outputs = (total: 1, spent: 0, withoutKeyImage: 1);
        addTearDown(session.dispose);
        await phone(tester);
        await tester.pumpWidget(
          MaterialApp(theme: darkTheme, home: KeyImagesScreen(session)),
        );

        // One block behind: the file may list a payment in it.
        await tester.tap(find.text('Choose file'));
        await tester.pumpAndSettle();
        expect(session.tries, 1);
        expect(find.text('Finishing sync first'), findsOne);
        session.height = 2001;
        session.dismissKeyImagesNotice(); // any change redraws the screens
        await tester.pumpAndSettle();
        expect(session.tries, 2);

        expect(find.text('Some outputs are missing'), findsOne);
        expect(
          find.textContaining('2 outputs this device never found'),
          findsOne,
        );
        expect(find.text('1234'), findsOne, reason: 'restore height here');
        expect(find.text('2 of 3'), findsOne, reason: 'outputs not found');

        await tester.tap(find.text('Rescan from an earlier height'));
        await tester.pumpAndSettle();
        expect(find.text('Advanced'), findsOne);
        expect(textIn(tester, find.byKey(const Key('rescanFrom'))), '1234');
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Some outputs are missing'), findsNothing);
        expect(find.text('Choose file'), findsOne);
        expect(three.existsSync(), isTrue, reason: "the user's own file");
      },
    );
  });

  testWidgets(
    'Settings → Advanced rescans from an earlier height, after asking',
    (tester) async {
      final session =
          _Rescans(
              watch(full, restoreHeight: 1234),
              publicNodes[Network.stagenet]!.first.host,
            )
            ..synced = true
            ..scanned = true
            ..height = 2000
            ..nodeHeight = 2000;
      await phone(tester);
      await tester.pumpWidget(MainApp(home: HomeScreen(session)));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Rescan, subaddress lookahead (50 × 200)'), findsOne);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      final from = find.byKey(const Key('rescanFrom'));
      expect(textIn(tester, from), '1234');
      await tester.enterText(from, '1300');
      await tester.pump();
      expect(find.textContaining('Use 1234 or an earlier height'), findsOne);
      expect(enabled(tester, 'Rescan'), isFalse);
      await tester.enterText(from, '1000');
      await tester.pump();
      expect(enabled(tester, 'Rescan'), isTrue);

      Future<void> rescan({required bool yes}) async {
        await tester.tap(find.widgetWithText(FilledButton, 'Rescan'));
        await tester.pumpAndSettle();
        expect(find.text('Rescan from block 1000?'), findsOne);
        await tester.tap(
          yes ? find.widgetWithText(TextButton, 'Rescan') : find.text('Cancel'),
        );
        await tester.pumpAndSettle();
      }

      await rescan(yes: false);
      expect(session.rescans, isEmpty);

      session.fail = true;
      await rescan(yes: true);
      expect(
        find.textContaining("Can't reach your node, so nothing"),
        findsOne,
      );
      expect(find.text('Advanced'), findsOne);

      session.fail = false;
      await rescan(yes: true);
      expect(session.rescans, [1000]);
      // Home shows the scan, as on the first sync, and asks for key images again
      // when it is done.
      expect(find.text('Advanced'), findsNothing);
      expect(find.text('Scanning the blockchain'), findsOne);
      session
        ..synced = true
        ..scanned = true
        ..height = 2000;
      session.dismissKeyImagesNotice(); // any change redraws the screens
      await tester.pumpAndSettle();
      expect(find.text('Import key images'), findsOne);

      // Taking the screens away closes the wallet.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Settings → Advanced raises the subaddress lookahead', (
    tester,
  ) async {
    final session =
        _OnNode(watch(full), publicNodes[Network.stagenet]!.first.host)
          ..synced = true
          ..scanned = true;
    addTearDown(session.dispose);
    await phone(tester);
    await tester.pumpWidget(
      MaterialApp(theme: darkTheme, home: AdvancedScreen(session)),
    );
    final accounts = find.descendant(
      of: find.byKey(const Key('lookaheadAccounts')),
      matching: find.byType(TextField),
    );
    expect(textIn(tester, accounts), '50');
    expect(enabled(tester, 'Save lookahead'), isFalse, reason: 'unchanged');

    final addresses = find.byKey(const Key('lookaheadAddresses'));
    await tester.enterText(addresses, '0');
    await tester.pump();
    expect(find.textContaining('Use at least 1 of each'), findsOne);
    expect(enabled(tester, 'Save lookahead'), isFalse);

    await tester.enterText(addresses, '300');
    await tester.pump();
    await tester.tap(find.text('Save lookahead'));
    await tester.pump();
    expect(find.text('Saving…'), findsOne);
    await settleWallet(tester, () => shows(find.text('Save lookahead')));
    expect(session.wallet.lookahead, (accounts: 50, addresses: 300));
    expect(enabled(tester, 'Save lookahead'), isFalse, reason: 'saved');
  });

  testWidgets('Settings shows the node, and Appearance switches the theme', (
    tester,
  ) async {
    final node = stagenetNode;
    final session = _OnNode(watch(full, restoreHeight: 1234), node)
      ..synced = true
      ..scanned = true;
    addTearDown(() => appearance.value = ThemeMode.system);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    Brightness shown() =>
        Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(shown(), Brightness.light, reason: 'System follows the phone');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(shown(), Brightness.dark);

    final real = askNode;
    final asked = <String>[];
    askNode = (node, {tor}) async {
      asked.add(node);
      return (height: 1, ms: 42);
    };
    addTearDown(() => askNode = real);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text(node), findsOne);
    // The node in use is asked once more, to time it.
    expect(find.text('Public node · connected · 42 ms'), findsOne);
    expect(asked, [node]);
    expect(find.text('1234'), findsOne);

    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('System')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(appearance.value, ThemeMode.light);
    expect(shown(), Brightness.light, reason: 'Light overrides the phone');
    expect(
      tester.getSemantics(find.text('Light')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('System')),
      isSemantics(isSelected: false),
    );
    semantics.dispose();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(shown(), Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(shown(), Brightness.dark, reason: 'Dark overrides the phone');
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(shown(), Brightness.light);

    // Taking the screen away closes the wallet.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the balance switches to USD, asking first while it is off', (
    tester,
  ) async {
    var asked = 0;
    usdPrice.fetch = () async {
      asked++;
      return 200; // a made-up price
    };
    addTearDown(() {
      usdPrice.on = false;
      usdPrice.fetch = fetchXmrUsd;
    });
    final session = _OnNode(watch(full), stagenetNode)
      ..synced = true
      ..scanned = true
      ..height = 2000
      ..nodeHeight = 2000
      ..balance = 2500000000000
      ..unlocked = 1500000000000;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));

    // Off, the default: the balance is XMR, and tapping it asks before any
    // price request.
    expect(find.text('tap for USD'), findsOne);
    await tester.tap(find.textContaining('2.5000'));
    await tester.pumpAndSettle();
    expect(find.text('Show the USD value?'), findsOne);
    expect(find.textContaining('Kraken sees your IP address'), findsOne);
    expect(asked, 0);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2.5000'), findsOne);
    expect(usdPrice.on, isFalse);
    expect(asked, 0);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Show USD value'), findsOne);
    Switch usdSwitch() => tester.widget<Switch>(
      find.descendant(
        of: find.byType(UsdSwitch),
        matching: find.byType(Switch),
      ),
    );
    expect(usdSwitch().value, isFalse);
    await tester.tap(find.text('Show USD value'));
    await tester.pump();
    expect(usdPrice.on, isTrue);
    expect(usdSwitch().value, isTrue);
    expect(asked, 1);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('tap for USD'), findsOne);
    expect(find.textContaining('2.5000'), findsOne, reason: 'starts in XMR');
    await tester.tap(find.textContaining('2.5000'));
    await tester.pump();
    expect(find.text('500.00 USD'), findsOne);
    expect(find.text(r'$300.00 unlocked · at $200.00 per XMR'), findsOne);
    expect(find.text('tap for XMR'), findsOne);
    await tester.tap(find.text('500.00 USD'));
    await tester.pump();
    expect(find.textContaining('2.5000'), findsOne);

    // A failed refresh keeps the price but says how old it is.
    usdPrice.fetch = () async => throw const SocketException('unreachable');
    await tester.pump(priceRefresh);
    await tester.tap(find.textContaining('2.5000'));
    await tester.pump();
    expect(find.text('500.00 USD'), findsOne);
    expect(find.textContaining('per XMR as of'), findsOne);

    // Turning it off goes back to XMR and forgets the price.
    usdPrice.on = false;
    await tester.pump();
    expect(find.textContaining('2.5000'), findsOne);
    expect(find.text('tap for USD'), findsOne);
    expect(usdPrice.perXmr, isNull);

    // Saying yes on Home turns the lookup on, as the Settings switch does,
    // and shows USD straight away.
    usdPrice.fetch = () async {
      asked++;
      return 200;
    };
    await tester.tap(find.textContaining('2.5000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show USD'));
    await tester.pumpAndSettle();
    expect(usdPrice.on, isTrue);
    expect(asked, 2);
    expect(find.text('500.00 USD'), findsOne);
    expect(find.text('tap for XMR'), findsOne);
    usdPrice.on = false; // stops the refresh timer before the test ends

    // Taking the screen away closes the wallet.
    await tester.pumpWidget(const SizedBox());
  });

  test('keeps the Appearance choice in a file between launches', () {
    final dir = Directory.systemTemp.createTempSync('mvw_test');
    final file = File('${dir.path}/app/appearance');
    addTearDown(() {
      appearance.value = ThemeMode.system;
      dir.deleteSync(recursive: true);
    });

    // First launch: nothing saved, and choosing Dark writes it down.
    var saving = keepAppearance(file);
    expect(appearance.value, ThemeMode.system);
    appearance.value = ThemeMode.dark;
    expect(file.readAsStringSync(), 'dark');
    appearance.removeListener(saving);

    // Next launch.
    appearance.value = ThemeMode.system;
    saving = keepAppearance(file);
    expect(appearance.value, ThemeMode.dark);
    appearance.removeListener(saving);

    // A file that says anything else falls back to System.
    file.writeAsStringSync('not a mode');
    saving = keepAppearance(file);
    expect(appearance.value, ThemeMode.system);
    appearance.removeListener(saving);
  });

  test('keeps the Show USD value choice in a file between launches', () {
    final dir = Directory.systemTemp.createTempSync('mvw_test');
    final file = File('${dir.path}/app/show_usd');
    var asked = 0;
    usdPrice.fetch = () async {
      asked++;
      return 200; // a made-up price
    };
    addTearDown(() {
      usdPrice.on = false;
      usdPrice.fetch = fetchXmrUsd;
      dir.deleteSync(recursive: true);
    });

    // First launch: nothing saved, so it is off and nothing is asked.
    var saving = keepShowUsd(file, hasWallet: true);
    expect(usdPrice.on, isFalse);
    expect(asked, 0);
    expect(file.existsSync(), isFalse);
    usdPrice.on = true;
    expect(file.readAsStringSync(), 'on');
    usdPrice.removeListener(saving);

    // Next launch: on again, and the price is asked for at once.
    usdPrice.on = false;
    asked = 0;
    saving = keepShowUsd(file, hasWallet: true);
    expect(usdPrice.on, isTrue);
    expect(asked, 1);
    usdPrice.on = false;
    expect(file.readAsStringSync(), 'off');
    usdPrice.removeListener(saving);

    // A launch with no wallet turns a saved "on" off without asking.
    file.writeAsStringSync('on');
    asked = 0;
    saving = keepShowUsd(file, hasWallet: false);
    expect(usdPrice.on, isFalse);
    expect(asked, 0);
    expect(file.readAsStringSync(), 'off');
    usdPrice.removeListener(saving);

    // A file that says anything else is off.
    file.writeAsStringSync('not a choice');
    saving = keepShowUsd(file, hasWallet: true);
    expect(usdPrice.on, isFalse);
    expect(asked, 0);
    usdPrice.removeListener(saving);
  });

  test('keeps a secret in Windows Credential Manager until it is deleted', () {
    const store = CredentialManager();
    const name = 'Monero View Wallet test: secret store';
    addTearDown(() => store.delete(name));
    expect(store.read(name), isNull);
    expect(store.write(name, 'not a real secret'), isTrue);
    expect(store.read(name), 'not a real secret');
    expect(store.write(name, 'replaced'), isTrue);
    expect(store.read(name), 'replaced');
    store.delete(name);
    expect(store.read(name), isNull);
  }, skip: Platform.isWindows ? false : 'Credential Manager is Windows only');

  test(
    'saves a wallet as two encrypted files, and deletes all of it',
    () async {
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      walletFile = '${dir.path}${Platform.pathSeparator}wallet';
      final passwordName = 'Monero View Wallet: $walletFile';
      addTearDown(() {
        ViewWallet.forgetSaved();
        walletFile = null;
        dir.deleteSync(recursive: true);
      });
      Set<String> files() => {
        for (final file in dir.listSync()) file.uri.pathSegments.last,
      };

      final address = full.address();
      final viewKey = full.secretViewKey();
      final wallet = ViewWallet.create(
        address: address,
        viewKey: viewKey,
        restoreHeight: 1234,
        save: true,
      );
      addTearDown(wallet.close);
      expect(wallet.isViewOnly, isTrue);
      expect(wallet.restoreHeight, 1234);
      await wallet.save({'mvw.test': 'a note'});
      expect(wallet.remembered('mvw.test'), 'a note');
      // wallet2's address file, written in plain text off mainnet, is gone.
      expect(files(), {'wallet', 'wallet.keys'});
      // With the network, which wallet2 needs before it opens the files.
      expect(
        secretStore.read(passwordName),
        matches(RegExp(r'^stagenet:[0-9a-f]{64}$')),
      );

      // wallet2 keeps the keys file locked while the wallet is open.
      await wallet.close();
      // Neither file shows the view key, as text or as bytes, or the address.
      final keyBytes = latin1.decode([
        for (var i = 0; i < 64; i += 2)
          int.parse(viewKey.substring(i, i + 2), radix: 16),
      ]);
      for (final name in files()) {
        final content = latin1.decode(
          File('${dir.path}/$name').readAsBytesSync(),
        );
        expect(content, isNot(contains(viewKey)), reason: name);
        expect(content, isNot(contains(keyBytes)), reason: name);
        expect(content, isNot(contains(address)), reason: name);
        expect(content, isNot(contains('a note')), reason: name);
      }

      // Checking a key against an address saves nothing.
      expect(
        ViewWallet.keysProblem(address: address, viewKey: viewKey),
        isNull,
      );
      expect(files(), {'wallet', 'wallet.keys'});

      await wallet.forget();
      expect(files(), isEmpty);
      expect(secretStore.read(passwordName), isNull);
    },
  );

  test('opens the saved wallet again without the keys', () async {
    final dir = Directory.systemTemp.createTempSync('mvw_test');
    walletFile = '${dir.path}${Platform.pathSeparator}wallet';
    final passwordName = 'Monero View Wallet: $walletFile';
    addTearDown(() {
      ViewWallet.forgetSaved();
      walletFile = null;
      dir.deleteSync(recursive: true);
    });
    ViewWallet create() => ViewWallet.create(
      address: full.address(),
      viewKey: full.secretViewKey(),
      restoreHeight: 1234,
      save: true,
    );
    expect(ViewWallet.openSaved(), isNull, reason: 'nothing is saved yet');
    expect(ViewWallet.savedButUnreadable, isFalse);

    // Setup that never reached "Start sync" starts over.
    var wallet = create();
    addTearDown(() => wallet.close());
    await wallet.close();
    expect(ViewWallet.openSaved(), isNull);
    expect(dir.listSync(), isEmpty);
    expect(secretStore.read(passwordName), isNull);

    // Stands in for the node, and counts who connects to it.
    final node = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(node.close);
    var callers = 0;
    node.listen((socket) {
      callers++;
      socket.destroy();
    });
    // Where the app's Tor would listen, were it running: nothing does.
    final builtIn = torAddress;
    torAddress = '127.0.0.1:9';
    addTearDown(() {
      torAddress = builtIn;
      torProxy = null;
    });

    // What connect() leaves, for a node reached over Tor (here the address an
    // earlier build saved, of a Tor Browser on this computer), and what
    // Receive leaves: a subaddress with a label.
    wallet = create();
    final subaddress = wallet.addSubaddress();
    final itsAddress = wallet.subaddress(subaddress);
    wallet.setLabel(subaddress, 'a label');
    await wallet.save({
      'mvw.node': '127.0.0.1:${node.port}',
      'mvw.tor': '127.0.0.1:9150',
    });
    await wallet.close();
    wallet = ViewWallet.openSaved()!;
    expect(wallet.address, full.address());
    expect(wallet.isViewOnly, isTrue);
    expect(wallet.restoreHeight, 1234);
    expect(wallet.node, '127.0.0.1:${node.port}');
    expect(wallet.tor, '127.0.0.1:9');
    expect(torProxy, '127.0.0.1:9', reason: 'the price lookup follows');
    expect(wallet.subaddressCount, subaddress + 1);
    expect(wallet.subaddress(subaddress), itsAddress);
    expect(wallet.label(subaddress), 'a label');
    // Tor isn't running: the session says the node can't be reached and keeps what
    // was saved, and the node is never asked directly instead.
    final session = WalletSession(wallet);
    await session.refresh();
    expect(session.reachable, isFalse);
    expect(session.balance, 0);
    expect(callers, 0);

    // Without its password the wallet can't be opened, and the app says so.
    await wallet.close();
    secretStore.delete(passwordName);
    expect(ViewWallet.openSaved(), isNull);
    expect(ViewWallet.savedButUnreadable, isTrue);
  });

  test(
    'opens a saved wallet on its own network, with the nodes added to the list',
    () async {
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      walletFile = '${dir.path}${Platform.pathSeparator}wallet';
      final passwordName = 'Monero View Wallet: $walletFile';
      addTearDown(() {
        ViewWallet.forgetSaved();
        walletFile = null;
        dir.deleteSync(recursive: true);
      });

      // What connect() leaves, here for a node nobody listens at.
      var wallet = watchSaved(full);
      await wallet.save({
        'mvw.node': '127.0.0.1:9',
        'mvw.added': 'a.example:38089 b.example:38089',
      });
      await wallet.close();
      // A build before mainnet kept the password alone.
      final saved = secretStore.read(passwordName)!;
      expect(saved, startsWith('stagenet:'));
      secretStore.write(passwordName, saved.substring('stagenet:'.length));
      wallet = ViewWallet.openSaved()!;
      expect(wallet.network, Network.stagenet);
      expect(wallet.address, full.address());
      expect(wallet.addedNodes, ['a.example:38089', 'b.example:38089']);
      await wallet.close();

      wallet = watchSaved(mainnetFull);
      expect(secretStore.read(passwordName), startsWith('mainnet:'));
      await wallet.save({'mvw.node': '127.0.0.1:9'});
      await wallet.close();
      wallet = ViewWallet.openSaved()!;
      expect(wallet.network, Network.mainnet);
      expect(wallet.address, mainnetFull.address());
      expect(wallet.addedNodes, isEmpty);
      await wallet.forget();

      // A network this build doesn't know: nothing is opened.
      wallet = watchSaved(full);
      await wallet.save({'mvw.node': '127.0.0.1:9'});
      await wallet.close();
      secretStore.write(
        passwordName,
        secretStore.read(passwordName)!.replaceFirst('stagenet', 'testnet'),
      );
      expect(ViewWallet.openSaved(), isNull);
      expect(ViewWallet.savedButUnreadable, isTrue);
    },
  );

  test('a session carries on from the notes the last one saved', () async {
    final dir = Directory.systemTemp.createTempSync('mvw_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final keyImages = '${dir.path}/key_images';
    expect(full.exportKeyImages(keyImages, all: true), isTrue);
    final wallet = watch(full);
    addTearDown(wallet.close);

    final first = WalletSession(wallet);
    expect(first.scanned, isFalse);
    expect(first.lastImport, isNull);
    first.scanned = true;
    final seen = first.lastContact = DateTime(2026, 10, 1, 9, 5);
    await first.importKeyImages(keyImages);

    final second = WalletSession(wallet);
    expect(second.scanned, isTrue);
    expect(second.lastContact, seen);
    expect(second.lastImport!.fileName, 'key_images');
    expect(
      second.lastImport!.at.millisecondsSinceEpoch,
      first.lastImport!.at.millisecondsSinceEpoch,
    );
    expect(second.lastImport!.outputs, first.lastImport!.outputs);

    // Notes that can't be read count as missing, so the app still starts.
    await wallet.save({
      'mvw.lastContact': 'not a time',
      'mvw.lastImport': '{"at": "not a number"}',
    });
    expect(WalletSession(wallet).lastImport, isNull);
    await wallet.save({'mvw.lastImport': 'not json'});
    expect(WalletSession(wallet).lastImport, isNull);
  });

  test('the wallet keeps the lock choice, on until turned off', () async {
    final wallet = watch(full);
    addTearDown(wallet.close);
    final first = WalletSession(wallet);
    expect(first.lockOn, isTrue);
    await first.setLockOn(false);
    expect(wallet.remembered('mvw.lock'), 'off');
    final second = WalletSession(wallet);
    expect(second.lockOn, isFalse);
    await second.setLockOn(true);
    expect(WalletSession(wallet).lockOn, isTrue);
  });

  test('the wallet keeps the Test speed choice, every node until '
      'turned off', () async {
    final wallet = watch(full);
    addTearDown(wallet.close);
    final first = WalletSession(wallet);
    expect(first.testAllNodes, isTrue);
    await first.setTestAllNodes(false);
    expect(wallet.remembered('mvw.speedTest'), 'picked');
    expect(WalletSession(wallet).testAllNodes, isFalse);
  });

  testWidgets('Settings can make Test speed ask only the node picked', (
    tester,
  ) async {
    final session = _OnNode(watch(full), stagenetNode)
      ..synced = true
      ..scanned = true;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test speed asks every node'));
    await tester.pumpAndSettle();
    expect(session.testAllNodes, isFalse);
    await tester.tap(find.text(stagenetNode));
    await tester.pumpAndSettle();
    expect(tester.widget<NodeScreen>(find.byType(NodeScreen)).testAll, isFalse);

    // Taking the screen away closes the wallet.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Settings turns the lock off only after Face ID or the passcode',
    (tester) async {
      final check = FakeCheck(Unlock.faceId);
      appLock = AppLock()..check = check;
      addTearDown(() => appLock = AppLock());
      final session = _OnNode(watch(full), stagenetNode)
        ..synced = true
        ..scanned = true;
      await appLock.start(on: session.lockOn);
      expect(appLock.locked, isTrue, reason: 'on by default');
      check.answers.add(CheckResult.ok);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await phone(tester);
      await tester.pumpWidget(MainApp(home: HomeScreen(session)));
      await tester.pump();
      expect(find.text('Wallet locked'), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      Switch lockSwitch() => tester.widget<Switch>(
        find.descendant(
          of: find.byType(LockSwitch),
          matching: find.byType(Switch),
        ),
      );
      expect(find.text('Face ID to open'), findsOne);
      expect(lockSwitch().value, isTrue);

      await tester.tap(find.text('Face ID to open'));
      await tester.pump();
      expect(check.asked.last, isTrue, reason: 'Face ID or the passcode');
      expect(lockSwitch().value, isTrue, reason: 'the check was cancelled');

      check.answers.add(CheckResult.ok);
      await tester.tap(find.text('Face ID to open'));
      await tester.pump();
      expect(lockSwitch().value, isFalse);
      expect(appLock.on, isFalse);
      expect(session.lockOn, isFalse);

      // Back on with no check: that only makes the app safer.
      final checks = check.asked.length;
      await tester.tap(find.text('Face ID to open'));
      await tester.pump();
      expect(lockSwitch().value, isTrue);
      expect(session.lockOn, isTrue);
      expect(check.asked, hasLength(checks));

      // Where nothing can check, the switch can't be turned on.
      appLock.kind = Unlock.none;
      appLock.on = false;
      await tester.pump();
      expect(lockSwitch().value, isFalse);
      expect(lockSwitch().onChanged, isNull);
      expect(find.textContaining("doesn't lock"), findsOne);

      // Taking the screens away closes the wallet.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Settings removes the wallet, after asking', (tester) async {
    usdPrice.fetch = () async => 200; // a made-up price
    usdPrice.on = true;
    addTearDown(() {
      usdPrice.on = false;
      usdPrice.fetch = fetchXmrUsd;
    });
    final session = _OnNode(watch(full), stagenetNode)
      ..synced = true
      ..scanned = true;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove wallet from this device'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this wallet?'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOne);
    expect(usdPrice.on, isTrue);

    await tester.tap(find.text('Remove wallet from this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await settleRemoving(tester);
    expect(find.text('Watch a wallet'), findsOne);
    expect(find.text('Settings'), findsNothing);
    expect(usdPrice.on, isFalse, reason: 'no price requests without a wallet');
  });

  testWidgets('the first scan shows progress while wallet2 gets ready', (
    tester,
  ) async {
    final session = _OnNode(watch(full, restoreHeight: 1000), stagenetNode)
      ..nodeHeight = 1500;
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    final ready = find.text(
      'Getting ready: listing the blocks before height 1000',
    );
    expect(ready, findsOne);
    expect(find.text('0%'), findsOne);

    // Below the restore height wallet2 is only listing blocks: the progress
    // counts from where the list first stood.
    Future<void> at(int height) async {
      session.height = height;
      session.dismissKeyImagesNotice(); // any change redraws the screens
      await tester.pump();
    }

    await at(400);
    expect(find.text('0%'), findsOne);
    await at(700);
    expect(find.text('50%'), findsOne);
    expect(ready, findsOne);

    // From the restore height on, blocks are scanned.
    await at(1000);
    expect(ready, findsNothing);
    expect(find.text('0 of 500 blocks · from height 1000'), findsOne);
    await at(1250);
    expect(find.text('50%'), findsOne);
    expect(find.text('250 of 500 blocks · from height 1000'), findsOne);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the first scan offers a way out, and setup says why it asks', (
    tester,
  ) async {
    final session = _OnNode(watch(full), stagenetNode);
    await phone(tester);
    await tester.pumpWidget(MainApp(home: HomeScreen(session)));
    expect(find.text('Scanning the blockchain'), findsOne);
    await tester.tap(find.text('Remove wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await settleRemoving(tester);
    expect(find.text('Watch a wallet'), findsOne);
    expect(find.textContaining("couldn't be opened"), findsNothing);

    await tester.pumpWidget(
      const MainApp(home: SetupScreen(lostSaved: true), key: Key('again')),
    );
    expect(find.textContaining("couldn't be opened"), findsOne);
  });

  test(
    'syncs to the tip of a stagenet node, and survives a bad node change',
    () async {
      final tip = (await ViewWallet.probeNode(node!)).height;
      expect(tip, greaterThan(2000000));

      final wallet = watch(full, restoreHeight: tip - 500);
      addTearDown(wallet.close);
      await wallet.connect(node);
      while (!wallet.isSynced) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(wallet.height, greaterThanOrEqualTo(tip));
      expect(wallet.balance, 0);

      // With the sync thread running, the import has to pause it first.
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(full.exportKeyImages('${dir.path}/key_images', all: true), isTrue);
      await wallet.importKeyImages('${dir.path}/key_images');

      // A rescan empties the wallet and scans again from an earlier height.
      await wallet.rescan(tip - 600);
      expect(wallet.restoreHeight, tip - 600);
      expect(wallet.isSynced, isFalse);
      expect(wallet.height, lessThan(tip));
      expect(wallet.remembered('mvw.restoreHeight'), '${tip - 600}');
      while (!wallet.isSynced) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(wallet.height, greaterThanOrEqualTo(tip));
      await wallet.importKeyImages('${dir.path}/key_images');

      await expectLater(
        wallet.connect('127.0.0.1:9'),
        throwsA(isA<WalletException>()),
      );
      expect(wallet.node, node);
      expect(await wallet.nodeHeight(), greaterThanOrEqualTo(tip));
    },
    skip: needsNode,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'first run on stagenet, then the next launch opens Home straight away',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      walletFile = '${dir.path}${Platform.pathSeparator}wallet';
      addTearDown(() {
        ViewWallet.forgetSaved();
        walletFile = null;
        dir.deleteSync(recursive: true);
      });
      final keyImages = '${dir.path}/key_images';
      expect(full.exportKeyImages(keyImages, all: true), isTrue);
      final dialog = pickKeyImagesFile;
      pickKeyImagesFile = () async => KeyImagesFile(keyImages);
      addTearDown(() => pickKeyImagesFile = dialog);

      // The wallet library works on real threads and sockets, which only move
      // while the test's fake clock is set aside.
      Future<void> letWalletWork() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump(const Duration(seconds: 2));
      }

      Future<void> until(Finder finder) async {
        for (var i = 0; i < 600 && finder.evaluate().isEmpty; i++) {
          await letWalletWork();
        }
        expect(finder, findsWidgets);
      }

      final tip = await tester.runAsync(
        () async => (await ViewWallet.probeNode(node!)).height,
      );
      await phone(tester);
      await tester.pumpWidget(const MainApp());
      await tester.enterText(address, full.address());
      await tester.enterText(viewKey, full.secretViewKey());
      await tester.enterText(restoreHeight, '${tip! - 500}');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('ownNode')), node!);
      await tester.pump();
      final fake = askNode;
      askNode = ViewWallet.probeNode;
      addTearDown(() => askNode = fake);
      await tester.tap(find.text('Test'));
      await until(find.textContaining('Reachable · block'));
      askNode = fake;
      await tester.tap(find.text('Start sync'));
      await until(find.text('Scanning the blockchain'));
      // While getting ready, or once scanning from there.
      expect(find.textContaining('height ${tip - 500}'), findsOne);

      // The scan finishes and the app asks for key images by itself.
      await until(find.text('Import key images'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Choose file'));
      await until(find.text('LAST IMPORT'));
      expect(find.text('key_images'), findsOne);
      // Done waits for the import to be saved.
      for (var i = 0; i < 60 && !enabled(tester, 'Done'); i++) {
        await letWalletWork();
      }
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Synced to block'), findsOne);
      expect(find.textContaining('0.0000'), findsWidgets);
      expect(find.text('No transactions yet.'), findsOne);
      expect(find.textContaining('Key images imported'), findsOne);

      // Close the app. wallet2 lets go of the keys file once the wallet has
      // closed, and then the next launch can open it.
      await tester.pumpWidget(const SizedBox());
      ViewWallet? saved;
      for (var i = 0; i < 60 && saved == null; i++) {
        await letWalletWork();
        saved = ViewWallet.openSaved();
      }
      final session = WalletSession(saved!)..startPolling();
      await tester.pumpWidget(
        MainApp(key: const Key('next launch'), home: HomeScreen(session)),
      );
      // Home at once, with what was saved: no setup, no first scan, and the
      // key images are still imported.
      expect(find.text('Watch a wallet'), findsNothing);
      expect(find.text('Scanning the blockchain'), findsNothing);
      expect(find.textContaining('Key images imported'), findsOne);
      expect(session.height, greaterThanOrEqualTo(tip));
      await until(find.textContaining('Synced to block'));
      expect(find.text('Import key images'), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text(node), findsOne);
      expect(find.text('${tip - 500}'), findsOne);

      // Rescan from an earlier height: the scan shows again, then Import key
      // images, as on the first run.
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rescanFrom')),
        '${tip - 600}',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Rescan'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Rescan'));
      await until(find.text('Scanning the blockchain'));
      await until(find.text('Import key images'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Choose file'));
      await until(find.text('LAST IMPORT'));
      for (var i = 0; i < 60 && !enabled(tester, 'Done'); i++) {
        await letWalletWork();
      }
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Key images imported'), findsOne);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('${tip - 600}'), findsOne);
      await tester.tap(find.text('Remove wallet from this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await until(find.text('Watch a wallet'));
      expect(dir.listSync().map((f) => f.uri.pathSegments.last), [
        'key_images',
      ], reason: 'the wallet files are gone');
      expect(ViewWallet.openSaved(), isNull);
    },
    skip: node == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Stands in for the device's secure storage where there is none.
class _MemoryStore implements SecretStore {
  final _secrets = <String, String>{};

  @override
  String? read(String name) => _secrets[name];

  @override
  bool write(String name, String secret) {
    _secrets[name] = secret;
    return true;
  }

  @override
  void delete(String name) => _secrets.remove(name);
}

/// A session that counts the saves asked of it.
class _CountingSaves extends WalletSession {
  _CountingSaves(super.wallet);

  int saves = 0;

  @override
  Future<void> save() {
    saves++;
    return super.save();
  }
}

/// A session that names [node] without connecting to it, for screens that
/// show the node.
class _OnNode extends WalletSession {
  _OnNode(super.wallet, this.node, {this.tor});

  @override
  final String node;

  @override
  final String? tor;
}

/// A session that keeps what each file it is asked to import says, instead of
/// importing it.
class _RecordsImports extends _OnNode {
  _RecordsImports(super.wallet, super.node);

  final imported = <String>[];

  @override
  Future<void> importKeyImages(String path) async =>
      imported.add(File(path).readAsStringSync());
}

/// A session whose rescan only says it started, or fails as it does when the
/// node can't be reached.
class _Rescans extends _OnNode {
  _Rescans(super.wallet, super.node);

  final rescans = <int>[];
  var fail = false;

  @override
  Future<void> rescan(int from) async {
    if (fail) throw WalletException("Can't reach the node.");
    rescans.add(from);
    scanned = synced = false;
    lastImport = null;
    height = 1;
    notifyListeners();
  }
}

/// A session whose imports fail with [error].
class _FailsImport extends _OnNode {
  _FailsImport(super.wallet, super.node, this.error);

  final String error;
  var tries = 0;

  @override
  Future<void> importKeyImages(String path) async {
    tries++;
    throw WalletException(error);
  }
}

/// Lets a test make real HTTP requests: testWidgets swaps HttpClient() for one
/// that answers 400 to everything.
class _NoOverrides extends HttpOverrides {}

/// Stands in for the app's Tor: it is connected at once, or fails to start
/// with [failure].
class _FakeTor extends BuiltInTor {
  String? failure;
  var stops = 0;

  @override
  Future<String> start() async {
    if (failure != null) throw TorException(failure!);
    progress = 100;
    return torAddress;
  }

  @override
  void stop() {
    stops++;
    progress = 0;
  }
}
