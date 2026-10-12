// Checks every public node the app offers (publicNodes in
// lib/node_screen.dart): it answers through the wallet library, on its
// network, synced with the others, and over TLS. An onion node is asked
// through the app's own Tor, which encrypts the connection end to end.
//
// It needs the internet, so it is skipped unless MVW_CHECK_PUBLIC_NODES is
// set. The Stagenet tests workflow runs it, on its own: it starts a Tor of
// its own on the port the other tests' Tor uses. Needs the wallet
// library and Tor: `sh tool/fetch_monero_c.sh` and `sh tool/fetch_tor.sh`.
//   MVW_CHECK_PUBLIC_NODES=1 flutter test test/public_nodes_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/node_screen.dart';
import 'package:monero_view_wallet/tor.dart';
import 'package:monero_view_wallet/wallet.dart';

void main() {
  final check = Platform.environment['MVW_CHECK_PUBLIC_NODES'] == null
      ? 'set MVW_CHECK_PUBLIC_NODES=1'
      : false;

  test(
    'every public node answers, on its network, synced and over TLS or Tor',
    () async {
      // Windows looks for DLLs in the current directory.
      Directory.current = 'windows/monero_c';
      torProgram = File('../tor/tor${Platform.isWindows ? '.exe' : ''}')
          .absolute
          .path;
      final folders = <Directory>[];
      addTearDown(() async {
        builtInTor.stop();
        // Tor lets go of its files a moment after it is told to stop.
        await Future<void>.delayed(const Duration(seconds: 2));
        for (final dir in folders) {
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Left in the temporary folder.
          }
        }
      });

      final problems = <String>[];
      // Tor can stall while it loads the Tor network's directory from a slow
      // relay. A second try, from a new folder, starts from another relay.
      String? tor;
      for (var tries = 1; tor == null && tries <= 2; tries++) {
        final dir = Directory.systemTemp.createTempSync('mvw_tor');
        folders.add(dir);
        torFolder = dir.path;
        try {
          tor = await builtInTor.start().timeout(const Duration(minutes: 3));
        } on TimeoutException {
          if (tries == 2) {
            problems.add(
              "Tor didn't connect in two tries (the second got to "
              '${builtInTor.progress}%), so the onion nodes were not checked. '
              'Its last lines:\n'
              '${builtInTor.notices.join('\n')}',
            );
          }
          builtInTor.stop();
        }
      }

      for (final MapEntry(key: network, value: nodes) in publicNodes.entries) {
        final heights = <String, int>{};
        for (final node in nodes) {
          final onion = isOnion(node.host);
          if (onion && tor == null) continue;
          var answer = await ViewWallet.probeNode(
            node.host,
            tor: onion ? tor : null,
          );
          // A node can miss one request, and Tor's first circuit to an onion
          // node often fails. Ask once more before calling it unreachable.
          if (answer.height == 0) {
            await Future<void>.delayed(const Duration(seconds: 30));
            answer = await ViewWallet.probeNode(
              node.host,
              tor: onion ? tor : null,
            );
          }
          final problem = answerProblem(network, answer);
          if (problem != null) {
            problems.add('${node.host}: $problem');
            continue;
          }
          heights[node.host] = answer.height;
          if (!onion && !await _offersTls(node.host)) {
            problems.add('${node.host}: no TLS');
          }
        }
        // A block or two behind is normal for a few seconds after a block.
        final tip = heights.values.fold(0, max);
        heights.forEach((host, height) {
          if (tip - height > 2) {
            problems.add('$host: ${tip - height} blocks behind');
          }
        });
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    },
    skip: check,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

/// Whether [node] ("host:port") takes a TLS connection. Only whether it does:
/// like wallet2, which these nodes' self-signed certificates would fail
/// otherwise, the certificate isn't checked.
Future<bool> _offersTls(String node) async {
  final colon = node.lastIndexOf(':');
  try {
    final socket = await SecureSocket.connect(
      node.substring(0, colon),
      int.parse(node.substring(colon + 1)),
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 20),
    );
    socket.destroy();
    return true;
  } on Exception {
    return false;
  }
}
