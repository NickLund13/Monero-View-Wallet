/// The app's own Tor (experimental): the Tor Project's tor. On Windows it is
/// the `tor` program, which ships with the app and runs as a separate process
/// while Tor is on. On iPhone, where an app can't start a program, it is the
/// same tor built as a library and run inside the app
/// (ios/Runner/InAppTor.swift). The wallet library is handed the address of
/// its SOCKS proxy (wallet.dart); the price lookup connects through it with
/// [throughTor].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The SOCKS proxy ("127.0.0.1:19050") the wallet reaches its node through,
/// or null while Tor is off. The wallet sets it when it connects, and the
/// price lookup follows it.
String? torProxy;

/// Where the app's Tor listens for SOCKS connections, on this device only.
/// Not 9050 or 9150, which a Tor service or Tor Browser on the same device
/// would already hold. Tests replace it.
String torAddress = '127.0.0.1:19050';

/// The `tor` program that ships with the app, or null in a build that has
/// none. main() sets it on Windows.
String? torProgram;

/// True in the iPhone build, which runs Tor inside the app with
/// [runTorInApp] instead of [torProgram]. main() sets it.
bool torInApp = false;

/// True if this build has Tor.
bool get hasTor => torInApp || torProgram != null;

/// Where the Tor inside the app takes commands (its control port), on this
/// device only. Only the app can use it: Tor asks for the cookie it writes in
/// [torFolder], which no other app can read. Tests replace it.
String torControlAddress = '127.0.0.1:19051';

/// Starts the Tor inside the app with these command-line arguments, on a
/// thread of its own (ios/Runner/InAppTor.swift). Answers "started",
/// "running" if it already was, or "exited" if it ran and stopped: Tor can run
/// only once in an app's life. Tests replace it.
Future<String?> Function(List<String> arguments) runTorInApp = (arguments) =>
    const MethodChannel('monero_view_wallet/tor')
        .invokeMethod<String>('start', arguments);

/// The folder Tor keeps its own files in between launches: what it knows of
/// the Tor network and the entry relays it has chosen. Nothing about the
/// wallet. main() sets it.
String? torFolder;

class TorException implements Exception {
  const TorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The percentage in one of Tor's "Bootstrapped 45% (…)" lines, or null for
/// any other line.
@visibleForTesting
int? bootstrapPercent(String line) {
  final match = RegExp(r'Bootstrapped (\d+)%').firstMatch(line);
  return match == null ? null : int.parse(match[1]!);
}

/// A connection to Tor's control port, as Tor's control-spec.txt describes
/// it: one command per line, each answered in order. The app sends only the
/// few commands [BuiltInTor] needs, and none of what it reads is logged.
class TorControl {
  TorControl._(this._socket) {
    _socket.done.ignore();
    const LineSplitter()
        .bind(const Utf8Decoder(allowMalformed: true).bind(_socket))
        .listen(
          (line) {
            _lines.add(line);
            _wake();
          },
          onError: (Object _) => _end(),
          onDone: _end,
        );
  }

  /// Connects to the control port at [address] and gives Tor the cookie it
  /// wrote to [cookie]. Tor opens the port and writes the cookie a moment
  /// after it starts, so this keeps trying for up to [within].
  static Future<TorControl> open(
    String address,
    File cookie, {
    Duration within = const Duration(seconds: 30),
  }) async {
    final colon = address.lastIndexOf(':');
    final trying = Stopwatch()..start();
    while (true) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          address.substring(0, colon),
          int.parse(address.substring(colon + 1)),
          timeout: const Duration(seconds: 5),
        );
        final control = TorControl._(socket);
        final hex = [
          for (final byte in cookie.readAsBytesSync())
            byte.toRadixString(16).padLeft(2, '0'),
        ].join();
        await control.command('AUTHENTICATE $hex');
        return control;
      } on Exception {
        socket?.destroy();
        if (trying.elapsed > within) {
          throw const TorException("Tor couldn't be started.");
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  final Socket _socket;
  final _lines = <String>[];
  var _more = Completer<void>();
  final _closed = Completer<void>();
  Future<void>? _last;

  /// Completes when the connection ends: Tor stopped, or [close] was called.
  Future<void> get done => _closed.future;

  bool get closed => _closed.isCompleted;

  void _wake() {
    _more.complete();
    _more = Completer();
  }

  void _end() {
    if (!_closed.isCompleted) _closed.complete();
    _wake();
  }

  void close() {
    _socket.destroy();
    _end();
  }

  Future<String> _line() async {
    while (_lines.isEmpty) {
      if (_closed.isCompleted) {
        throw const TorException('Tor closed its control connection.');
      }
      await _more.future;
    }
    return _lines.removeAt(0);
  }

  /// Sends [command] after the ones before it have been answered, and returns
  /// the lines of Tor's answer. Throws [TorException] if Tor refuses it.
  /// Answers that carry data over several lines ("250+") aren't read, since
  /// the app asks for none.
  Future<List<String>> command(String command) {
    final before = _last;
    final answer = () async {
      await before;
      _socket.write('$command\r\n');
      final lines = [await _line()];
      // "250-…" lines go on; the one with a space after the code ends it.
      while (lines.last.length < 4 || lines.last[3] != ' ') {
        lines.add(await _line());
      }
      if (!lines.last.startsWith('250 ')) {
        // Not the command itself, which may hold the cookie.
        throw TorException(
          'Tor refused ${command.split(' ').first}: ${lines.last}',
        );
      }
      return lines;
    }();
    _last = answer.then((_) {}, onError: (Object _) {});
    return answer;
  }

  /// How far Tor is in connecting to the Tor network, 0 to 100, and Tor's
  /// line saying so.
  Future<(int, String)> bootstrap() async {
    final lines = await command('GETINFO status/bootstrap-phase');
    final line = lines.firstWhere(
      (line) => line.contains('status/bootstrap-phase='),
      orElse: () => '',
    );
    final match = RegExp(r'PROGRESS=(\d+)').firstMatch(line);
    if (match == null) {
      throw const TorException("Tor didn't say how far it got.");
    }
    return (int.parse(match[1]!), line);
  }
}

/// Runs [torProgram], or the Tor inside the app where [torInApp], and follows
/// how far it is in connecting to the Tor network.
class BuiltInTor extends ChangeNotifier {
  Process? _process;
  Future<String>? _start;

  /// Counts the stops, so a start that was stopped meanwhile (and perhaps
  /// started again) knows it no longer counts.
  int _runs = 0;

  /// The control connection to the Tor inside the app, which runs from its
  /// first start until the app ends. Null until it is first needed, and
  /// again once a connection has ended.
  Future<TorControl>? _control;
  TorControl? _live;

  /// Whether the Tor inside the app has been started in this launch, and
  /// whether it has ended since.
  bool _inAppStarted = false;
  bool _inAppEnded = false;

  /// Completes when the Tor that was stopped last has gone: until then it
  /// still holds the port and the folder the next one needs. Null when none
  /// was. Not a completed future made up front: that one would belong to the
  /// zone that first touched [builtInTor], a test's fake one for instance, and
  /// waiting for it elsewhere would never end.
  Future<void>? _gone;

  /// How far Tor is in connecting to the Tor network, 0 to 100.
  int progress = 0;

  /// Why the last start failed, until a later one gets going. Null if none
  /// has.
  String? error;

  /// True once connections can be made through it.
  bool get ready => progress == 100;

  /// The last lines Tor printed, for a test to show when Tor doesn't connect.
  /// Kept in memory only, and never shown, saved or logged by the app. At
  /// Tor's notice level they hold no addresses Tor connects to.
  @visibleForTesting
  final notices = <String>[];

  /// Starts Tor unless it is already running. Completes with its proxy
  /// address once Tor is connected to the Tor network, which takes from a few
  /// seconds to a minute or more; Tor keeps trying for as long as it runs.
  /// Throws [TorException] if this build has no Tor or Tor stops first.
  Future<String> start() => _start ??= () async {
    final run = _runs;
    try {
      return await _launch(run);
    } catch (e) {
      // Unless it was stopped meanwhile: then a later start may be running.
      if (run == _runs) {
        error = e is TorException ? e.message : "Tor couldn't be started.";
        stop();
      }
      rethrow;
    }
  }();

  /// Stops Tor. Whatever still connects through [torAddress] then fails.
  void stop() {
    _runs++;
    final process = _process;
    if (process != null) {
      process.kill();
      _gone = process.exitCode.then((_) {});
    }
    if (torInApp) _takeOffline();
    _process = null;
    _start = null;
    progress = 0;
    notifyListeners();
  }

  Future<String> _launch(int run) async {
    final program = torProgram;
    final folder = torFolder;
    if (torInApp && folder != null) return _launchInApp(run, folder);
    if (program == null || folder == null || !File(program).existsSync()) {
      throw const TorException('This build has no Tor yet.');
    }
    if (_gone case final gone?) {
      await gone;
      _gone = null;
      if (run != _runs) throw const TorException('Tor was stopped.');
    }
    final Process process;
    try {
      process = _process = await Process.start(
        program,
        [
          // Only the settings given here: not a torrc a Tor installed on this
          // device may have left in its usual place.
          '-f', '$folder${Platform.pathSeparator}torrc',
          '--ignore-missing-torrc',
          '--defaults-torrc', '$folder${Platform.pathSeparator}torrc-defaults',
          '--DataDirectory', folder,
          '--SocksPort', torAddress,
          '--ClientOnly', '1',
          '--AvoidDiskWrites', '1',
          // Read below for the progress, and kept nowhere.
          '--Log', 'notice stdout',
          // Tor exits when the app does, even if the app is killed.
          '--__OwningControllerProcess', '$pid',
        ],
        // The Linux build of tor loads the libraries that ship next to it.
        environment: Platform.isLinux
            ? {'LD_LIBRARY_PATH': File(program).parent.path}
            : null,
      );
    } on ProcessException {
      throw const TorException("Tor couldn't be started.");
    }
    final connected = Completer<void>();
    notices.clear();
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (!identical(_process, process)) return;
          notices.add(line);
          if (notices.length > 20) notices.removeAt(0);
          final percent = bootstrapPercent(line);
          if (percent == null) return;
          progress = percent;
          error = null;
          notifyListeners();
          if (percent == 100 && !connected.isCompleted) connected.complete();
        });
    process.stderr.drain<void>();
    process.exitCode.then((_) {
      if (!connected.isCompleted) {
        connected.completeError(
          const TorException('Tor stopped before it connected.'),
        );
      } else if (identical(_process, process)) {
        // It died while in use. The next start runs it again.
        stop();
      }
    });
    await connected.future;
    return torAddress;
  }

  /// Starts the Tor inside the app the first time, puts it on the network and
  /// follows its progress through its control port.
  Future<String> _launchInApp(int run, String folder) async {
    final opening = _control ??= _openInApp(folder);
    final TorControl control;
    try {
      control = await opening;
    } catch (_) {
      if (identical(_control, opening)) _control = null;
      rethrow;
    }
    if (run != _runs) throw const TorException('Tor was stopped.');
    await control.command('SETCONF DisableNetwork=0');
    notices.clear();
    while (true) {
      final (percent, line) = await control.bootstrap();
      if (run != _runs) throw const TorException('Tor was stopped.');
      if (notices.lastOrNull != line) {
        notices.add(line);
        if (notices.length > 20) notices.removeAt(0);
      }
      if (percent != progress) {
        progress = percent;
        error = null;
        notifyListeners();
      }
      if (percent == 100) return torAddress;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<TorControl> _openInApp(String folder) async {
    _inAppStarted = true;
    final state = await runTorInApp(inAppTorArguments(folder));
    if (state == 'exited') {
      _inAppEnded = true;
      throw const TorException(
        'Tor stopped. Close and open the app again to restart it.',
      );
    }
    final control = _live = await TorControl.open(
      torControlAddress,
      File('$folder${Platform.pathSeparator}control_auth_cookie'),
    );
    control.done.then((_) {
      if (!identical(_live, control)) return;
      _live = null;
      _control = null;
      // Tor ended, or the connection was lost while Tor runs on. Either way
      // the app no longer controls it, so it is stopped: a Tor that still
      // runs is taken off the network over a new connection, and the next
      // start puts it back on.
      stop();
    });
    return control;
  }

  /// The Tor inside the app can't run twice in one launch, so stopping it
  /// takes it off the network instead: it closes its SOCKS port and every
  /// connection made through it. Over a new control connection if the last
  /// one ended; commands go in order, so this comes after any start's.
  void _takeOffline() {
    final folder = torFolder;
    if (!_inAppStarted || _inAppEnded || folder == null) return;
    final opening = _control ??= _openInApp(folder);
    void cantStop() {
      error =
          "Tor couldn't be taken off the network. Close the app to stop it.";
      notifyListeners();
    }

    opening.then(
      (control) => control
          .command('SETCONF DisableNetwork=1')
          .then(
            (_) {},
            // A lost connection is dealt with as it ends (see _openInApp).
            onError: (Object _) => control.closed ? null : cantStop(),
          ),
      onError: (Object _) {
        if (identical(_control, opening)) _control = null;
        // Once Tor has ended it is off the network.
        if (!_inAppEnded) cantStop();
      },
    );
  }
}

/// The command line the Tor inside the app is started with, keeping its files
/// in [folder]. It starts off the network: [BuiltInTor.start] puts it on.
List<String> inAppTorArguments(String folder) => [
  // Only the settings given here, as for the tor program.
  '-f', '$folder${Platform.pathSeparator}torrc',
  '--ignore-missing-torrc',
  '--defaults-torrc', '$folder${Platform.pathSeparator}torrc-defaults',
  '--DataDirectory', folder,
  '--SocksPort', torAddress,
  '--ControlPort', torControlAddress,
  '--CookieAuthentication', '1',
  '--ClientOnly', '1',
  '--AvoidDiskWrites', '1',
  '--DisableNetwork', '1',
  // Prints nothing: the progress comes through the control port.
  '--quiet',
];

/// The one Tor the app runs. Tests replace it.
BuiltInTor builtInTor = BuiltInTor();

/// True for an onion address, which only Tor can reach.
bool isOnion(String node) =>
    node.toLowerCase().contains(RegExp(r'\.onion(:\d+)?$'));

/// A connection to [host]:[port] made by the Tor at [proxy] (SOCKS5, RFC
/// 1928). [host] goes to Tor as a name, so Tor looks it up and this device's
/// DNS resolver never sees it.
///
/// The socket comes back already listened to, which [SecureSocket.secure]
/// takes over; nothing else can read from it.
Future<Socket> socksConnect(String proxy, String host, int port) async {
  final colon = proxy.lastIndexOf(':');
  final socket = await Socket.connect(
    proxy.substring(0, colon),
    int.parse(proxy.substring(colon + 1)),
    timeout: const Duration(seconds: 5),
  );
  final got = <int>[];
  var closed = false;
  var more = Completer<void>();
  void wake() {
    more.complete();
    more = Completer();
  }

  socket.listen(
    (chunk) {
      got.addAll(chunk);
      wake();
    },
    onError: (Object _) {
      closed = true;
      wake();
    },
    onDone: () {
      closed = true;
      wake();
    },
  );
  Future<List<int>> read(int count) async {
    while (got.length < count) {
      if (closed) throw const SocketException('Tor closed the connection.');
      await more.future;
    }
    final bytes = got.sublist(0, count);
    got.removeRange(0, count);
    return bytes;
  }

  Future<void> handshake() async {
    socket.add([5, 1, 0]); // SOCKS5, offering one method: no authentication
    final method = await read(2);
    if (method[0] != 5 || method[1] != 0) {
      throw const SocketException('The Tor proxy refused the connection.');
    }
    final name = ascii.encode(host);
    // Connect (1) to a name (3) of this length, then the port.
    socket.add([5, 1, 0, 3, name.length, ...name, port >> 8, port & 0xff]);
    final reply = await read(4);
    if (reply[0] != 5 || reply[1] != 0) {
      throw const SocketException("Tor couldn't reach the host.");
    }
    // The rest of the reply is the address Tor connected from, and its port.
    await read(switch (reply[3]) {
      1 => 4 + 2,
      4 => 16 + 2,
      _ => (await read(1))[0] + 2,
    });
  }

  try {
    // Tor may have to build a circuit first.
    await handshake().timeout(const Duration(seconds: 60));
    return socket;
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

/// For [HttpClient.connectionFactory]: makes every connection through the Tor
/// at [proxy], then starts TLS with the certificate checked against the
/// host's name. There is no direct connection to fall back to, so if Tor is
/// not running the request fails. Only https goes through.
Future<ConnectionTask<Socket>> Function(Uri, String?, int?) throughTor(
  String proxy,
) => (url, _, _) async {
  if (!url.isScheme('https')) {
    throw ArgumentError.value(url.scheme, 'url', 'only https goes over Tor');
  }
  Socket? socket;
  var cancelled = false;
  Future<Socket> connect() async {
    final plain = socket = await socksConnect(proxy, url.host, url.port);
    if (cancelled) {
      plain.destroy();
      throw const SocketException('Cancelled.');
    }
    return socket = await SecureSocket.secure(plain, host: url.host);
  }

  return ConnectionTask.fromSocket(connect(), () {
    cancelled = true;
    socket?.destroy();
  });
};
