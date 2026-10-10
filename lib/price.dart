/// The opt-in USD price lookup, the one network call besides the node
/// (SECURITY.md rule 5). Nothing is fetched until the person turns it on: with
/// Settings → Show USD value, or by saying yes when they tap the balance on
/// Home. It then asks one source for the XMR price in USD over TLS, through
/// Tor when Tor is on, and the request carries no wallet data.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'tor.dart';

/// Kraken's public XMR/USD ticker: no account or API key, and the same URL the
/// Monero GUI asks for its own price display. Kraken sees the IP address and
/// the time, never anything about the wallet.
final krakenTicker = Uri.https('api.kraken.com', '/0/public/Ticker', {
  'pair': 'XMRUSD',
});

/// Makes the connection for each price request, over TLS with the certificate
/// checked: direct while Tor is off, and through Tor while the wallet reaches
/// its node through Tor. Tor then also looks up Kraken's name, and the request
/// itself is the same.
HttpClient Function() priceClient = () {
  final tor = torProxy;
  final client = HttpClient();
  if (tor != null) {
    client
      ..connectionFactory = throughTor(tor)
      // Not also through a proxy named in this device's environment.
      ..findProxy = (_) => 'DIRECT';
  }
  return client;
};

/// How often the price is asked for again while the setting is on.
const priceRefresh = Duration(minutes: 10);

/// Far more than Kraken's answer (about 500 bytes) needs.
const _maxAnswer = 64 * 1024;

class PriceException implements Exception {
  const PriceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// USD per XMR from [krakenTicker]. Throws if Kraken can't be reached or its
/// answer has no price.
Future<double> fetchXmrUsd() => readPrice(krakenTicker, priceClient());

/// Asks [url] for the price through [client], then closes [client]. A redirect
/// is refused, not followed, so no other host is ever contacted.
@visibleForTesting
Future<double> readPrice(Uri url, HttpClient client) async {
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw PriceException('The price source answered ${response.statusCode}.');
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      body.add(chunk);
      if (body.length > _maxAnswer) {
        throw const PriceException("The price source's answer is too long.");
      }
    }
    return parseKrakenTicker(utf8.decode(body.takeBytes()));
  } finally {
    client.close(force: true);
  }
}

/// The last trade price in Kraken's ticker answer, which looks like
/// `{"error":[],"result":{"XXMRZUSD":{"c":["<price>","<volume>"],…}}}`.
@visibleForTesting
double parseKrakenTicker(String answer) {
  if (jsonDecode(answer) case {
    'error': List(isEmpty: true),
    'result': {'XXMRZUSD': {'c': [String last, ...]}},
  }) {
    final price = double.tryParse(last);
    if (price != null && price.isFinite && price > 0) return price;
  }
  throw const PriceException("Kraken's answer has no XMR price.");
}

/// "1,234.56" for 1234.561: whole cents, thousands separated by commas.
String formatUsd(double dollars) {
  final cents = (dollars * 100).round();
  final whole = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  return '$whole.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Show USD value (Settings, or a yes on Home), and the price while it is on.
/// Off by default.
/// The price is held in memory only; main() keeps the choice between
/// launches.
class UsdPrice extends ChangeNotifier {
  /// The lookup. Tests replace it.
  Future<double> Function() fetch = fetchXmrUsd;

  bool _on = false;
  bool _asking = false;
  Timer? _timer;

  /// Counts the switch's changes, so an answer that arrives after the switch
  /// was turned off (or off and on again) is dropped.
  int _turn = 0;

  /// USD per XMR. Null until the first answer, and whenever the switch is off.
  double? perXmr;

  /// When [perXmr] arrived.
  DateTime? at;

  /// True if the last try failed. [perXmr], if any, is from an earlier one.
  bool failed = false;

  bool get on => _on;

  /// Turning it on asks for the price at once and then every [priceRefresh].
  /// Turning it off stops asking and forgets the price.
  set on(bool value) {
    if (value == _on) return;
    _on = value;
    _turn++;
    _timer?.cancel();
    _timer = null;
    _asking = false;
    perXmr = null;
    at = null;
    failed = false;
    if (value) {
      _timer = Timer.periodic(priceRefresh, (_) => refresh());
      refresh();
    } else {
      notifyListeners();
    }
  }

  /// True while a request is out.
  bool get asking => _asking;

  /// Asks for the price now, unless the switch is off or a request is already
  /// out.
  Future<void> refresh() async {
    if (!_on || _asking) return;
    final turn = _turn;
    _asking = true;
    notifyListeners();
    try {
      final price = await fetch();
      if (turn == _turn) {
        perXmr = price;
        at = DateTime.now();
        failed = false;
      }
    } catch (_) {
      if (turn == _turn) failed = true;
    }
    if (turn == _turn) {
      _asking = false;
      notifyListeners();
    }
  }
}

/// The one price lookup the app has.
final usdPrice = UsdPrice();
