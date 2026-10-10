// The opt-in USD price lookup, checked without the wallet library and without
// reaching Kraken: the requests go to a server on this computer.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/price.dart';

/// Kraken's answer for the XMR/USD ticker, cut down to the fields the app
/// reads, with a made-up price.
const _ticker =
    '{"error":[],"result":{"XXMRZUSD":{"a":["200.10000000","1","1.000"],'
    '"c":["200.00000000","0.05000000"],"o":"190.00000000"}}}';

/// A real HTTP client. testWidgets swaps HttpClient() for one that answers 400
/// to everything, which would hide what readPrice does with real answers.
HttpClient direct() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _NoOverrides());

class _NoOverrides extends HttpOverrides {}

void main() {
  test('asks Kraken for the XMR/USD price and nothing else', () {
    // The whole request: no address, key, balance or anything else from the
    // wallet goes in it.
    expect(
      krakenTicker.toString(),
      'https://api.kraken.com/0/public/Ticker?pair=XMRUSD',
    );
  });

  test("reads the last trade price from Kraken's answer", () {
    expect(parseKrakenTicker(_ticker), 200.0);
    for (final bad in [
      '{"error":["EQuery:Unknown asset pair"]}',
      '{"error":[],"result":{}}',
      '{"error":[],"result":{"XXMRZUSD":{"c":[]}}}',
      '{"error":[],"result":{"XXMRZUSD":{"c":["0.00000000","1"]}}}',
      '{"error":[],"result":{"XXMRZUSD":{"c":["NaN","1"]}}}',
      '{"error":[],"result":{"XXMRZUSD":{"c":[200,1]}}}',
    ]) {
      expect(
        () => parseKrakenTicker(bad),
        throwsA(isA<PriceException>()),
        reason: bad,
      );
    }
    expect(() => parseKrakenTicker('<html>'), throwsFormatException);
  });

  test('formats USD in cents with thousands separated', () {
    expect(formatUsd(0), '0.00');
    expect(formatUsd(0.005), '0.01');
    expect(formatUsd(999.994), '999.99');
    expect(formatUsd(1234.5), '1,234.50');
    expect(formatUsd(1234567.891), '1,234,567.89');
  });

  group('the request', () {
    late HttpServer server;
    late List<HttpRequest> seen;
    late void Function(HttpResponse response) answer;

    Uri url([String path = '/0/public/Ticker']) =>
        Uri.http('127.0.0.1:${server.port}', path, {'pair': 'XMRUSD'});

    setUp(() async {
      seen = [];
      answer = (response) => response.write(_ticker);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        seen.add(request);
        await request.drain<void>();
        answer(request.response);
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('is one plain GET with no cookies, body or other headers', () async {
      expect(await readPrice(url(), direct()), 200.0);
      expect(seen, hasLength(1));
      final request = seen.single;
      expect(request.method, 'GET');
      expect(request.uri.toString(), '/0/public/Ticker?pair=XMRUSD');
      expect(request.contentLength, lessThanOrEqualTo(0));
      final headers = <String>{};
      request.headers.forEach((name, _) => headers.add(name));
      expect(headers, {'host', 'user-agent', 'accept-encoding'});
    });

    test('never follows a redirect to another server', () async {
      final elsewhere = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => elsewhere.close(force: true));
      var contacted = false;
      elsewhere.listen((request) {
        contacted = true;
        request.response.close();
      });
      answer = (response) => response
        ..statusCode = HttpStatus.found
        ..headers.set('location', 'http://127.0.0.1:${elsewhere.port}/');

      await expectLater(
        readPrice(url(), direct()),
        throwsA(isA<PriceException>()),
      );
      expect(contacted, isFalse);
    });

    test('refuses an error status or an answer that is too long', () async {
      answer = (response) => response.statusCode = 503;
      await expectLater(
        readPrice(url(), direct()),
        throwsA(isA<PriceException>()),
      );

      answer = (response) => response.add(utf8.encode(' ' * 100000));
      await expectLater(
        readPrice(url(), direct()),
        throwsA(isA<PriceException>()),
      );
    });
  });

  group('Show USD value', () {
    // A test clock, so the ten-minute refresh can be checked.
    testWidgets('makes no request until it is turned on', (tester) async {
      final price = UsdPrice();
      var asked = 0;
      price.fetch = () async {
        asked++;
        return 200;
      };
      expect(price.on, isFalse);
      await tester.pump(priceRefresh * 3);
      expect(asked, 0);
      await price.refresh();
      expect(asked, 0, reason: 'refresh does nothing while off');

      price.on = true;
      await tester.pump();
      expect(asked, 1, reason: 'asks at once');
      expect(price.perXmr, 200);
      expect(price.at, isNotNull);
      await tester.pump(priceRefresh);
      expect(asked, 2, reason: 'and again every ten minutes');

      price.on = false;
      expect(price.perXmr, isNull, reason: 'off forgets the price');
      await tester.pump(priceRefresh * 3);
      expect(asked, 2, reason: 'off stops asking');
    });

    testWidgets('keeps the last price when a refresh fails, and drops answers '
        'that come after it was turned off', (tester) async {
      final price = UsdPrice();
      var fail = false;
      price.fetch = () async {
        if (fail) throw const SocketException('unreachable');
        return 200;
      };
      price.on = true;
      await tester.pump();
      expect(price.failed, isFalse);

      fail = true;
      await tester.pump(priceRefresh);
      expect(price.failed, isTrue);
      expect(price.perXmr, 200, reason: 'shown with the time it was fetched');

      price.on = false;
      price.on = true;
      await tester.pump();
      expect(price.failed, isTrue);
      expect(price.perXmr, isNull);

      // An answer that was still on its way when the switch went off.
      price.on = false;
      final late = Future<double>.delayed(
        const Duration(seconds: 5),
        () => 300,
      );
      price.fetch = () => late;
      price.on = true;
      price.on = false;
      await tester.pump(const Duration(seconds: 5));
      expect(price.perXmr, isNull);
      expect(price.asking, isFalse);
    });
  });
}
