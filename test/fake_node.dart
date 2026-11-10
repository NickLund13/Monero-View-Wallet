import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Stands in for a stagenet node, on this computer only. It knows its version
/// and its [height], which is all wallet2 asks before it counts the node as
/// connected, and has no blocks: a scan asks for them and gets nothing.
class FakeNode {
  FakeNode._(this._server, this.height) {
    _server.listen(_answer);
  }

  static Future<FakeNode> start({required int height}) async => FakeNode._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    height,
  );

  final HttpServer _server;

  /// The height the node says the chain has.
  final int height;

  /// How long each answer takes, as a node far away or behind Tor does.
  Duration delay = Duration.zero;

  /// How many times it has said its version, which wallet2 asks once each
  /// time it connects.
  int connections = 0;

  /// "host:port", as the app takes a node.
  String get address => '127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  // Where stagenet's rules changed (monero's src/hardforks/hardforks.cpp).
  // wallet2 refuses a node that doesn't know all of them.
  static const _hardForks = [
    1, 32000, 33000, 34000, 35000, 36000, 37000, 176456, //
    177176, 269000, 269720, 454721, 675405, 676125, 1151000, 1151720,
  ];

  Future<void> _answer(HttpRequest request) async {
    final response = request.response;
    try {
      final body = await request.fold(
        <int>[],
        (all, some) => all..addAll(some),
      );
      Object? result;
      if (request.uri.path == '/json_rpc') {
        final method = (jsonDecode(utf8.decode(body)) as Map)['method'];
        if (method == 'get_version') {
          result = {
            'status': 'OK',
            'version': 3 << 16 | 14,
            'release': true,
            'current_height': height,
            'target_height': height,
            'hard_forks': [
              for (final (i, at) in _hardForks.indexed)
                {'hf_version': i + 1, 'height': at},
            ],
          };
        } else if (method == 'get_info') {
          result = {
            'status': 'OK',
            'height': height,
            'target_height': height,
            'stagenet': true,
            'nettype': 'stagenet',
            'synchronized': true,
          };
        }
      }
      await Future<void>.delayed(delay);
      if (result case {'version': _}) connections++;
      // Anything else, the blocks a scan asks for among them: not here.
      final answer = result == null
          ? const <int>[]
          : utf8.encode(
              jsonEncode({'jsonrpc': '2.0', 'id': '0', 'result': result}),
            );
      response
        ..statusCode = result == null ? HttpStatus.notFound : HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..contentLength = answer.length
        ..add(answer);
      await response.close();
    } on Object {
      // wallet2 hangs up on an answer it doesn't like.
    }
  }
}
