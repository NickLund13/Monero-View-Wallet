/// Reading a view-only wallet QR code at setup (docs/design/DESIGN.md, 1a):
/// the Monero GUI's View Only Wallet code or Feather's View-Only QR, or, for
/// wallets that show neither, the primary address and then the private view
/// key, each on its own. Anything that carries spend authority is refused
/// whole, before any field is read.
///
/// The decoded text is only ever held in memory. Nothing here logs it or
/// writes it anywhere.
library;

import 'dart:convert';
import 'dart:isolate';

import 'wallet.dart';

/// What a scanned code fills in on Setup: a view-only wallet code fills all
/// three, an address alone only the address, and a private view key alone
/// only the view key.
typedef WalletQr = ({String? address, String? viewKey, int? restoreHeight});

/// Why a scanned code was refused, one card each on Scan wallet QR.
enum Refusal {
  /// It holds a spend key or a seed.
  spendKey,

  /// It is no view-only wallet code the app reads, or something in it is not
  /// what such a code holds.
  notWalletCode,

  /// Its address is a testnet one.
  testnet,

  /// Its address is a subaddress, not the wallet's primary address.
  subaddress,

  /// It is a private key alone, and there is no primary address to check it
  /// against yet.
  needsAddress,

  /// Its view key isn't the address's view key, so it may be the spend key.
  keyMismatch,

  /// The view key check couldn't be made, so nothing in it was confirmed.
  unchecked,
}

class RefusedCode implements Exception {
  RefusedCode(this.reason);
  final Refusal reason;
  @override
  String toString() => 'RefusedCode(${reason.name})';
}

/// The wallet in [text], a scanned QR code's text, checked in DESIGN.md's
/// order: spend authority, the format, the values, and last the view key
/// against the address with [keysProblem] (ViewWallet.keysProblem's
/// contract), by default on a helper isolate. A private key alone is checked
/// against [address], the one Setup already has. Throws [RefusedCode] if any
/// check fails or can't be made, and then nothing from the code is kept.
Future<WalletQr> readWalletQr(
  String text, {
  String? address,
  Future<String?> Function({required String address, required String viewKey})
      keysProblem =
      _keysProblemOffUi,
}) async {
  // 1. Spend authority.
  if (_carriesSpendAuthority(text)) throw RefusedCode(Refusal.spendKey);

  // 2. One of the formats.
  final trimmed = text.trim();
  if (_viewKeyPattern.hasMatch(trimmed)) {
    // A private key alone, as Stack Wallet shows each key: only the address
    // tells the view key from the spend key, so there must be one.
    if (address == null) throw RefusedCode(Refusal.needsAddress);
    try {
      _checkAddress(address);
    } on RefusedCode {
      throw RefusedCode(Refusal.needsAddress);
    }
    final problem = await _keyProblem(keysProblem, address, trimmed);
    if (problem == 'failed to parse address') {
      throw RefusedCode(Refusal.needsAddress);
    }
    if (problem != null) throw RefusedCode(Refusal.keyMismatch);
    return (address: null, viewKey: trimmed, restoreHeight: null);
  }
  if (_addressAlone(trimmed) case final alone?) {
    _checkAddress(alone);
    return (address: alone, viewKey: null, restoreHeight: null);
  }
  final fields = _guiFields(text) ?? _featherFields(text);
  if (fields == null) throw RefusedCode(Refusal.notWalletCode);
  final (address: codeAddress, :viewKey, :height) = fields;

  // 3. A primary address of a network the app watches, a view key that can be
  // one, and a whole number for the height.
  _checkAddress(codeAddress);
  if (!_viewKeyPattern.hasMatch(viewKey) || height == null || height < 0) {
    throw RefusedCode(Refusal.notWalletCode);
  }

  // 4. The view key against the address: a key that isn't this address's
  // view key may be the spend key.
  final problem = await _keyProblem(keysProblem, codeAddress, viewKey);
  if (problem == 'failed to parse address') {
    throw RefusedCode(Refusal.notWalletCode);
  }
  if (problem != null) throw RefusedCode(Refusal.keyMismatch);
  return (address: codeAddress, viewKey: viewKey, restoreHeight: height);
}

/// Throws [RefusedCode] unless [address] can be a primary address of a
/// network the app watches.
void _checkAddress(String address) {
  if (!_addressPattern.hasMatch(address)) {
    throw RefusedCode(Refusal.notWalletCode);
  }
  // Testnet primary addresses start with 9 or A: prefix 53 in base58.
  if (address.startsWith('9') || address.startsWith('A')) {
    throw RefusedCode(Refusal.testnet);
  }
  // Subaddresses start with 8 on mainnet and 7 on stagenet.
  if (address.startsWith('8') || address.startsWith('7')) {
    throw RefusedCode(Refusal.subaddress);
  }
  if (networkOf(address) == null) throw RefusedCode(Refusal.notWalletCode);
}

/// [keysProblem]'s answer for [viewKey] and [address]. A check that can't be
/// made accepts nothing.
Future<String?> _keyProblem(
  Future<String?> Function({required String address, required String viewKey})
  keysProblem,
  String address,
  String viewKey,
) async {
  try {
    return await keysProblem(address: address, viewKey: viewKey);
  } catch (_) {
    throw RefusedCode(Refusal.unchecked);
  }
}

/// ViewWallet.keysProblem off the UI isolate: the wallet it checks with takes
/// a third of a second to make, which would stall the screen. That wallet is
/// in memory only and freed on the helper isolate before it ends.
Future<String?> _keysProblemOffUi({
  required String address,
  required String viewKey,
}) => Isolate.run(
  () => ViewWallet.keysProblem(address: address, viewKey: viewKey),
);

final _addressPattern = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{95}$');
final _viewKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// 12 or more words in a row, in any script: what a seed phrase looks like
/// (BIP39 12 to 24 words, Polyseed 16, Monero's own 25).
final _wordRun = RegExp(r'(?:\p{L}+[\s,;+]+){11,}\p{L}+', unicode: true);

/// A parameter or field named for a spend key or seed, in any case and
/// spelling: spend_key, spendKey, privateSpendKey, seed, mnemonic_seed.
bool _spendName(String name) {
  final letters = name.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  return letters.contains('spend') ||
      letters.contains('seed') ||
      letters.contains('mnemonic');
}

/// [text] with %XX and + decoded, or as it is if it can't be decoded.
String _decoded(String text) {
  try {
    return Uri.decodeQueryComponent(text);
  } on FormatException {
    return text;
  } on ArgumentError {
    return text;
  }
}

bool _carriesSpendAuthority(String text) {
  if (_wordRun.hasMatch(text) || _wordRun.hasMatch(_decoded(text))) {
    return true;
  }
  // The names of every parameter after the first ?, whatever the scheme.
  final query = text.indexOf('?');
  if (query >= 0) {
    for (final part in text.substring(query + 1).split(RegExp('[&;?#]'))) {
      final equals = part.indexOf('=');
      final name = equals < 0 ? part : part.substring(0, equals);
      if (_spendName(_decoded(name))) return true;
    }
  }
  // Every field name and text value of a JSON code, however deep.
  final json = _json(text);
  if (json != null) {
    bool carries(Object? value) => switch (value) {
      Map() => value.entries.any(
        (field) => _spendName('${field.key}') || carries(field.value),
      ),
      List() => value.any(carries),
      String() => _wordRun.hasMatch(value),
      _ => false,
    };
    if (carries(json)) return true;
  }
  return false;
}

Object? _json(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
}

typedef _Fields = ({String address, String viewKey, int? height});

/// The Monero GUI's View Only Wallet code,
/// `monero-wallet:<address>?view_key=<key>&height=<height>`, also with the
/// `monero_wallet:` that Cake Wallet reads. Nothing else may be in it.
_Fields? _guiFields(String text) {
  final match = RegExp(
    r'^monero[-_]wallet:([^?#]*)\?([^#]*)$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  final parameters = <String, String>{};
  for (final part in match[2]!.split('&')) {
    final equals = part.indexOf('=');
    if (equals < 0) return null;
    final name = _decoded(part.substring(0, equals));
    if (parameters.containsKey(name)) return null;
    parameters[name] = _decoded(part.substring(equals + 1));
  }
  final viewKey = parameters['view_key'];
  final height = parameters['height'];
  if (parameters.length != 2 || viewKey == null || height == null) {
    return null;
  }
  return (
    address: match[1]!,
    viewKey: viewKey,
    height: _digits.hasMatch(height) ? int.tryParse(height) : null,
  );
}

final _digits = RegExp(r'^[0-9]+$');

/// An address on its own, as receive screens show it: bare, or in a
/// `monero:` payment request with only the request's own fields
/// (wallet2::parse_uri: tx_amount, tx_payment_id, recipient_name and
/// tx_description), which are ignored.
String? _addressAlone(String text) {
  if (_addressPattern.hasMatch(text)) return text;
  final match = RegExp(
    r'^monero:([^?#]*)(?:\?([^#]*))?$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final query = match[2];
  if (query != null) {
    final seen = <String>{};
    for (final part in query.split('&')) {
      final equals = part.indexOf('=');
      if (equals < 0) return null;
      final name = _decoded(part.substring(0, equals));
      if (!_paymentFields.contains(name) || !seen.add(name)) return null;
    }
  }
  return match[1]!;
}

const _paymentFields = {
  'tx_amount',
  'tx_payment_id',
  'recipient_name',
  'tx_description',
};

/// Feather Wallet's View-Only QR: compact JSON with version 0, the primary
/// address, the private view key, the restore height and the wallet's name,
/// which is ignored. Nothing else may be in it.
_Fields? _featherFields(String text) {
  final json = _json(text);
  if (json is! Map<String, Object?>) return null;
  const known = {
    'version',
    'primaryAddress',
    'privateViewKey',
    'restoreHeight',
    'walletName',
  };
  if (!known.containsAll(json.keys) || json['version'] != 0) return null;
  final address = json['primaryAddress'];
  final viewKey = json['privateViewKey'];
  final height = json['restoreHeight'];
  if (address is! String || viewKey is! String) return null;
  return (
    address: address,
    viewKey: viewKey,
    height: switch (height) {
      int() => height,
      String() when _digits.hasMatch(height) => int.tryParse(height),
      _ => null,
    },
  );
}
