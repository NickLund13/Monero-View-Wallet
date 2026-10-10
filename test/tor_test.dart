// Tor routing of the price lookup and the launcher of the app's own Tor,
// checked without the wallet library and without the Tor network: servers on
// this computer stand in for Tor's proxy and control port, and the real tor
// program is only started where it gives up before it connects to anything.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/price.dart';
import 'package:monero_view_wallet/tor.dart';

/// A stand-in for Tor's SOCKS5 proxy. It notes what it is asked to connect
/// to, answers [reply] (0 means connected) and hangs up, so nothing beyond
/// this computer is contacted.
Future<({String address, List<String> asked})> fakeTor({int reply = 0}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  final asked = <String>[];
  server.listen((socket) {
    final got = <int>[];
    var greeted = false, answered = false;
    socket.listen((chunk) {
      got.addAll(chunk);
      if (!greeted && got.length >= 3) {
        greeted = true;
        got.removeRange(0, 3);
        socket.add([5, 0]); // no authentication
      }
      if (greeted && !answered && got.length > 4 && got.length >= 7 + got[4]) {
        answered = true;
        final end = 5 + got[4];
        final name = ascii.decode(got.sublist(5, end));
        asked.add('type ${got[3]} $name:${got[end] << 8 | got[end + 1]}');
        socket.add([5, reply, 0, 1, 0, 0, 0, 0, 0, 0]);
        socket.close();
      }
    }, onError: (_) {});
  });
  return (address: '127.0.0.1:${server.port}', asked: asked);
}

/// A stand-in for the control port of the Tor inside the app. It writes a
/// made-up cookie into [folder] as Tor would, wants it back before anything
/// else, answers the bootstrap question with each of [progress] in turn,
/// refuses [refuse], and notes the commands that follow the cookie. Its
/// [sockets] are the connections made to it, and [drop] ends them as if they
/// were lost.
Future<
  ({
    String address,
    List<String> commands,
    List<Socket> sockets,
    void Function() drop,
  })
>
fakeControl(Directory folder, List<int> progress, {String? refuse}) async {
  final cookie = List<int>.generate(32, (i) => i); // made up
  File('${folder.path}/control_auth_cookie').writeAsBytesSync(cookie);
  final hex = [for (final b in cookie) b.toRadixString(16).padLeft(2, '0')];
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  void drop() {
    for (final socket in sockets) {
      socket.destroy();
    }
  }

  addTearDown(() async {
    drop();
    await server.close();
  });
  final commands = <String>[];
  var asked = 0;
  server.listen((socket) {
    sockets.add(socket);
    var authenticated = false;
    const LineSplitter().bind(utf8.decoder.bind(socket)).listen((line) {
      if (!authenticated) {
        authenticated = line == 'AUTHENTICATE ${hex.join()}';
        socket.write(authenticated ? '250 OK\r\n' : '515 Bad cookie\r\n');
        return;
      }
      commands.add(line);
      if (line == refuse) {
        socket.write('552 Made up\r\n');
      } else if (line == 'GETINFO status/bootstrap-phase') {
        final percent = progress[min(asked++, progress.length - 1)];
        socket.write(
          '250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=$percent '
          'TAG=made_up SUMMARY="Made up"\r\n250 OK\r\n',
        );
      } else {
        socket.write('250 OK\r\n');
      }
    }, onError: (_) {});
  });
  return (
    address: '127.0.0.1:${server.port}',
    commands: commands,
    sockets: sockets,
    drop: drop,
  );
}

/// Waits up to two seconds for [done].
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// The app's own price client, as a real one (see price_test.dart).
HttpClient client() =>
    HttpOverrides.runWithHttpOverrides(priceClient, _NoOverrides());

class _NoOverrides extends HttpOverrides {}

void main() {
  tearDown(() => torProxy = null);

  test('tells an onion node from any other', () {
    final onion = '${'a' * 56}.onion'; // made up
    expect(isOnion('$onion:18081'), isTrue);
    expect(isOnion('${onion.toUpperCase()}:18081'), isTrue);
    expect(isOnion(onion), isTrue);
    expect(isOnion('$onion.:18081'), isTrue, reason: "the root's dot");
    expect(isOnion('$onion.'), isTrue);
    expect(isOnion('node.example.org:18081'), isFalse);
    expect(isOnion('onion.example.org:18081'), isFalse);
    expect(isOnion('192.168.1.20:18081'), isFalse);
  });

  test("reads Tor's progress from its own lines", () {
    expect(
      bootstrapPercent(
        'Oct 09 12:00:00.000 [notice] Bootstrapped 45% '
        '(requesting_descriptors): Asking for relay descriptors',
      ),
      45,
    );
    expect(bootstrapPercent('[notice] Bootstrapped 100% (done): Done'), 100);
    expect(bootstrapPercent('[notice] Opening Socks listener'), isNull);
  });

  group("the app's own Tor", () {
    final program = File('windows/tor/tor${Platform.isWindows ? '.exe' : ''}')
        .absolute
        .path;
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mvw_tor'));
    tearDown(() {
      builtInTor.stop();
      torProgram = torFolder = null;
      dir.deleteSync(recursive: true);
    });

    test('a build without the tor program says so', () async {
      torFolder = dir.path;
      await expectLater(
        builtInTor.start(),
        throwsA(
          isA<TorException>().having(
            (e) => e.message,
            'message',
            'This build has no Tor yet.',
          ),
        ),
      );
      torProgram = '${dir.path}/not_there';
      await expectLater(builtInTor.start(), throwsA(isA<TorException>()));
      expect(builtInTor.error, 'This build has no Tor yet.');
    });

    test(
      'runs the tor program, and says when it stops before it connects',
      () async {
        // A file where Tor's folder should be: tor gives up at once, before
        // it contacts anything.
        final notAFolder = File('${dir.path}/file')..writeAsStringSync('');
        torProgram = program;
        torFolder = notAFolder.path;
        for (var again = 0; again < 2; again++) {
          await expectLater(
            builtInTor.start(),
            throwsA(
              isA<TorException>().having(
                (e) => e.message,
                'message',
                'Tor stopped before it connected.',
              ),
            ),
          );
          expect(builtInTor.ready, isFalse);
          expect(builtInTor.error, 'Tor stopped before it connected.');
        }
      },
      skip: File(program).existsSync() ? false : 'run sh tool/fetch_tor.sh',
    );

    test(
      'a start right after a stop is not undone by the stopped Tor',
      () async {
        // Stands in for tor: says how far it got, then waits to be stopped.
        final fake = File('${dir.path}/tor')
          ..writeAsStringSync(
            '#!/bin/sh\n'
            'echo "[notice] Bootstrapped 10% (conn): Connecting to a relay"\n'
            'exec sleep 60\n',
          );
        Process.runSync('chmod', ['+x', fake.path]);
        torProgram = fake.path;
        torFolder = dir.path;
        final tor = BuiltInTor();
        tor.start().ignore();
        while (tor.progress < 10) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        tor.stop();
        final again = tor.start()..ignore();
        // The first one ends, before it ever connected, while this one waits.
        while (tor.progress < 10) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(tor.progress, 10);
        expect(tor.error, isNull);
        expect(tor.start(), same(again));
        tor.stop();
      },
      skip: Platform.isWindows ? 'the stand-in is a shell script' : false,
    );
  });

  group('the Tor inside the app (iPhone)', () {
    final realRun = runTorInApp;
    final realControl = torControlAddress;
    late Directory dir;
    late List<List<String>> launched;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('mvw_tor');
      launched = [];
      torInApp = true;
      torFolder = dir.path;
      runTorInApp = (arguments) async {
        launched.add(arguments);
        return launched.length == 1 ? 'started' : 'running';
      };
    });
    tearDown(() {
      torInApp = false;
      torFolder = null;
      runTorInApp = realRun;
      torControlAddress = realControl;
      dir.deleteSync(recursive: true);
    });

    test('starts once, and stopping only takes it off the network', () async {
      final control = await fakeControl(dir, [0, 45, 100]);
      torControlAddress = control.address;
      final tor = BuiltInTor();
      expect(await tor.start(), torAddress);
      expect(tor.ready, isTrue);
      final arguments = launched.single.join(' ');
      expect(arguments, contains('--SocksPort $torAddress'));
      expect(arguments, contains('--ControlPort ${control.address}'));
      expect(arguments, contains('--CookieAuthentication 1'));
      expect(arguments, contains('--DataDirectory ${dir.path}'));
      // Off the network until the app has its control connection.
      expect(arguments, contains('--DisableNetwork 1'));
      expect(control.commands, [
        'SETCONF DisableNetwork=0',
        for (var i = 0; i < 3; i++) 'GETINFO status/bootstrap-phase',
      ]);

      tor.stop();
      expect(tor.ready, isFalse);
      await until(() => control.commands.last == 'SETCONF DisableNetwork=1');
      expect(await tor.start(), torAddress);
      expect(launched, hasLength(1));
      expect(control.commands.reversed.take(2), [
        'GETINFO status/bootstrap-phase',
        'SETCONF DisableNetwork=0',
      ]);
      tor.stop();
    });

    test('a stop before it is on the network keeps it off', () async {
      final control = await fakeControl(dir, [100]);
      torControlAddress = control.address;
      final tor = BuiltInTor();
      final starting = tor.start();
      tor.stop();
      await expectLater(starting, throwsA(isA<TorException>()));
      expect(tor.error, isNull);
      await until(() => control.commands.isNotEmpty);
      expect(control.commands, ['SETCONF DisableNetwork=1']);
    });

    test(
      'a lost control connection takes it off the network over a new one',
      () async {
        final control = await fakeControl(dir, [100]);
        torControlAddress = control.address;
        final tor = BuiltInTor();
        expect(await tor.start(), torAddress);
        control.drop();
        await until(() => control.sockets.length == 2);
        await until(() => control.commands.last == 'SETCONF DisableNetwork=1');
        expect(tor.ready, isFalse);
        expect(tor.error, isNull);
        // Asked again, and found still running: not a second Tor.
        expect(launched, hasLength(2));

        // The next start puts it back on over the new connection.
        expect(await tor.start(), torAddress);
        expect(control.sockets, hasLength(2));
        expect(control.commands.reversed.take(2), [
          'GETINFO status/bootstrap-phase',
          'SETCONF DisableNetwork=0',
        ]);
        tor.stop();
        await until(() => control.commands.last == 'SETCONF DisableNetwork=1');
      },
    );

    test('once Tor has ended, stopping asks it nothing', () async {
      final control = await fakeControl(dir, [100]);
      torControlAddress = control.address;
      var ended = false;
      runTorInApp = (arguments) async {
        launched.add(arguments);
        if (ended) return 'exited';
        return launched.length == 1 ? 'started' : 'running';
      };
      final tor = BuiltInTor();
      expect(await tor.start(), torAddress);
      ended = true;
      control.drop();
      await until(() => launched.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(control.sockets, hasLength(1));
      expect(tor.error, isNull);

      await expectLater(tor.start(), throwsA(isA<TorException>()));
      expect(
        tor.error,
        'Tor stopped. Close and open the app again to restart it.',
      );
    });

    test("says so when Tor won't go off the network", () async {
      final control = await fakeControl(dir, [
        100,
      ], refuse: 'SETCONF DisableNetwork=1');
      torControlAddress = control.address;
      final tor = BuiltInTor();
      expect(await tor.start(), torAddress);
      tor.stop();
      await until(() => tor.error != null);
      expect(
        tor.error,
        "Tor couldn't be taken off the network. Close the app to stop it.",
      );
    });

    test('says when Tor has ended for this launch', () async {
      runTorInApp = (_) async => 'exited';
      final tor = BuiltInTor();
      await expectLater(tor.start(), throwsA(isA<TorException>()));
      expect(
        tor.error,
        'Tor stopped. Close and open the app again to restart it.',
      );
    });

    test('the control port is only used with the right cookie', () async {
      final control = await fakeControl(dir, [100]);
      File('${dir.path}/control_auth_cookie').writeAsBytesSync([1, 2, 3]);
      await expectLater(
        TorControl.open(
          control.address,
          File('${dir.path}/control_auth_cookie'),
          within: const Duration(milliseconds: 300),
        ),
        throwsA(
          isA<TorException>().having(
            (e) => e.message,
            'message',
            "Tor couldn't be started.",
          ),
        ),
      );
      expect(control.commands, isEmpty);
    });
  });

  test('with Tor on, the price request is handed to Tor by name', () async {
    final tor = await fakeTor();
    torProxy = tor.address;
    // The stand-in connects to nothing and hangs up, so TLS never starts.
    await expectLater(readPrice(krakenTicker, client()), throwsA(anything));
    // Type 3 is a name: Tor looks Kraken up, not this computer's DNS.
    expect(tor.asked, ['type 3 api.kraken.com:443']);
  });

  test("fails when Tor can't reach the price source", () async {
    final tor = await fakeTor(reply: 4); // host unreachable
    torProxy = tor.address;
    await expectLater(
      readPrice(krakenTicker, client()),
      throwsA(isA<SocketException>()),
    );
    expect(tor.asked, hasLength(1));
  });

  test('with Tor on but not running, nothing is asked directly', () async {
    // Stands in for the price source, and counts who connects to it.
    final source = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(source.close);
    var callers = 0;
    source.listen((socket) {
      callers++;
      socket.destroy();
    });
    // A port nothing listens on, where Tor's proxy would be.
    final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    torProxy = '127.0.0.1:${gone.port}';
    await gone.close();

    await expectLater(
      readPrice(Uri.parse('https://127.0.0.1:${source.port}/'), client()),
      throwsA(isA<SocketException>()),
    );
    expect(callers, 0);
  });

  test('only https goes over Tor', () async {
    final tor = await fakeTor();
    torProxy = tor.address;
    await expectLater(
      readPrice(Uri.parse('http://price.invalid/'), client()),
      throwsA(isA<ArgumentError>()),
    );
    expect(tor.asked, isEmpty);
  });
}
