/// Reading the animated QR codes that signing devices show: Blockchain
/// Commons' Uniform Resources ("UR"), as the Monero wallets that use them
/// write them. A code's text is `ur:<type>/<body>` for a message that fits in
/// one QR code, and `ur:<type>/<n>-<m>/<body>` for part n of a message sent in
/// m parts, shown one after the other. Parts after the m-th each mix several
/// parts together (a fountain code), so a reader that missed a part can still
/// finish from later ones.
///
/// A port of the decoder in bc-ur, Blockchain Commons' reference code, in the
/// version the wallet library is built with (github.com/MrCyjaneK/bc-ur at
/// d82e7c75). The wallet library has that decoder inside but doesn't expose
/// it, and it can't say how far a scan has got. This code only puts the
/// message back together; the wallet library decrypts it and checks what is
/// in it.
///
/// The ported parts are Copyright © 2020 Blockchain Commons, LLC, under the
/// BSD-2-Clause-Patent license (SPDX-License-Identifier: BSD-2-Clause-Patent);
/// its conditions and disclaimer are in assets/licenses/bc-ur.txt, which the
/// app shows under Settings → Open-source licenses. Xoshiro256** is by David
/// Blackman and Sebastiano Vigna, in the public domain (CC0).
///
/// Scanned text is held in memory only. Nothing here logs it or writes it
/// anywhere.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// The type of the UR code [text], in lower case, or null if [text] is no UR
/// code. Read the code itself with a [UrReader] of that type.
String? urType(String text) {
  final path = _path(text);
  return path?.first;
}

/// The components of a UR code's path, the type first, or null if [text] is
/// no UR code. Case doesn't count: QR codes often hold UR codes in capitals.
List<String>? _path(String text) {
  final lower = text.toLowerCase();
  if (!lower.startsWith('ur:')) return null;
  // Empty components are left out, as bc-ur's split does.
  final path = [
    for (final component in lower.substring(3).split('/'))
      if (component.isNotEmpty) component,
  ];
  if (path.length < 2 || !_typePattern.hasMatch(path.first)) return null;
  return path;
}

final _typePattern = RegExp(r'^[a-z0-9-]+$');

/// The most parts a message may be sent in. Far more than anyone would wait
/// to scan (at five codes a second, half an hour), and it keeps what a code
/// that claims more can make the reader do in check.
const maxUrParts = 10000;

/// Puts one message of [type] back together from its UR codes, scanned in any
/// order, with gaps and repeats. Codes of other types are not for it: check
/// [urType] first.
class UrReader {
  UrReader(this.type);

  /// The UR type read, such as `xmr-keyimage`.
  final String type;

  /// The message once complete: the UR's CBOR, as the sender's UR encoder
  /// was given it.
  Uint8List? get message => _message;
  Uint8List? _message;

  bool get complete => _message != null;

  /// How many of the message's parts are known, of [partsTotal]. Both are 0
  /// until a part has been read.
  int get partsKnown =>
      _message != null ? partsTotal : _fountain?._simple.length ?? 0;
  int get partsTotal => _fountain?.seqLen ?? (_message != null ? 1 : 0);

  _Fountain? _fountain;

  /// Takes one scanned code of [type]. Returns true if it brought the message
  /// further: a part not known before, or the whole message. A code that
  /// can't be read, or of another type, changes nothing.
  ///
  /// A part of another message of [type], as when the sending device made a
  /// new code, starts the reading over with that message.
  bool add(String text) {
    if (_message != null) return false;
    final path = _path(text);
    if (path == null || path.first != type) return false;
    if (path.length == 2) {
      // A message that fits in one code.
      final cbor = _fromBytewords(path[1]);
      if (cbor == null) return false;
      _message = cbor;
      return true;
    }
    if (path.length != 3) return false;
    final part = _Part.read(path[1], path[2]);
    if (part == null) return false;
    var fountain = _fountain;
    if (fountain == null || !fountain.sameMessage(part)) {
      fountain = _fountain = _Fountain(part);
    }
    final known = fountain._simple.length;
    if (!fountain.receive(part)) {
      // Put together, but not what the sender checksummed: start over.
      _fountain = null;
      return false;
    }
    _message = fountain.message;
    return _message != null || fountain._simple.length > known;
  }

  /// The complete message as one UR code, as a sender writes a message that
  /// fits in one: what the wallet library reads back.
  String get asOneCode => 'ur:$type/${toBytewords(_message!)}';

  /// The bytes the complete message carries: the content of the CBOR byte
  /// string it is, as the Monero wallets write it. Null if it isn't one.
  Uint8List? get bytes {
    final message = _message;
    if (message == null) return null;
    try {
      return _Cbor(message).byteString();
    } on FormatException {
      return null;
    }
  }
}

/// One part of a message sent in several codes: the CBOR array [seqNum,
/// seqLen, messageLen, checksum, fragment] in bytewords.
class _Part {
  _Part(this.seqNum, this.seqLen, this.messageLen, this.checksum, this.data);

  final int seqNum;
  final int seqLen;
  final int messageLen;

  /// The CRC-32 of the whole message.
  final int checksum;
  final Uint8List data;

  /// The part in [body], whose `n-m` [sequence] must agree with it. Null for
  /// anything else, and for a part that can't belong to a well-formed
  /// message.
  static _Part? read(String sequence, String body) {
    final match = RegExp(r'^([0-9]{1,10})-([0-9]{1,10})$').firstMatch(sequence);
    final cbor = _fromBytewords(body);
    if (match == null || cbor == null) return null;
    try {
      final reader = _Cbor(cbor);
      if (reader.head(4) != 5) return null;
      final seqNum = reader.head(0);
      final seqLen = reader.head(0);
      final messageLen = reader.head(0);
      final checksum = reader.head(0);
      final data = reader.byteString();
      if (seqNum != int.parse(match[1]!) || seqLen != int.parse(match[2]!)) {
        return null;
      }
      // Each message is cut into seqLen fragments of the same length, the
      // last one padded with zeros.
      if (seqNum < 1 ||
          seqNum > 0xFFFFFFFF ||
          seqLen < 1 ||
          seqLen > maxUrParts ||
          checksum > 0xFFFFFFFF ||
          data.isEmpty ||
          messageLen > seqLen * data.length ||
          messageLen <= (seqLen - 1) * data.length) {
        return null;
      }
      return _Part(seqNum, seqLen, messageLen, checksum, data);
    } on FormatException {
      return null;
    }
  }
}

/// A part of the message as the fountain decoder holds it: the fragments
/// mixed into it, and their XOR.
class _Mixed {
  _Mixed(this.indexes, this.data);

  final Set<int> indexes;
  final Uint8List data;

  bool get simple => indexes.length == 1;

  /// The same for the same set of fragments.
  String get key => (indexes.toList()..sort()).join(',');

  /// This part with [other]'s fragments taken out, if [other] holds some of
  /// this part's fragments and nothing else. Otherwise this part.
  _Mixed reducedBy(_Mixed other) {
    if (other.indexes.length >= indexes.length ||
        !indexes.containsAll(other.indexes)) {
      return this;
    }
    final data = Uint8List.fromList(this.data);
    for (var i = 0; i < data.length; i++) {
      data[i] ^= other.data[i];
    }
    return _Mixed(indexes.difference(other.indexes), data);
  }
}

/// bc-ur's FountainDecoder for one message: the parts of [seqLen] fragments.
class _Fountain {
  _Fountain(_Part first)
    : seqLen = first.seqLen,
      _messageLen = first.messageLen,
      _checksum = first.checksum,
      _fragmentLen = first.data.length;

  final int seqLen;
  final int _messageLen;
  final int _checksum;
  final int _fragmentLen;

  /// The fragments known, by index.
  final _simple = <int, Uint8List>{};

  /// Parts that still mix several fragments, by [_Mixed.key].
  var _mixed = <String, _Mixed>{};
  final _queue = <_Mixed>[];
  _Sampler? _degrees;

  Uint8List? message;

  bool sameMessage(_Part part) =>
      part.seqLen == seqLen &&
      part.messageLen == _messageLen &&
      part.checksum == _checksum &&
      part.data.length == _fragmentLen;

  /// Takes [part], one of this message's. False if the message, once put
  /// together, doesn't match its checksum.
  bool receive(_Part part) {
    if (message != null) return true;
    _queue.add(_Mixed(_fragments(part), part.data));
    while (message == null && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (next.simple) {
        if (!_addSimple(next)) return false;
      } else {
        _addMixed(next);
      }
    }
    return true;
  }

  bool _addSimple(_Mixed part) {
    final index = part.indexes.single;
    if (_simple.containsKey(index)) return true;
    _simple[index] = part.data;
    if (_simple.length < seqLen) {
      _reduceMixedBy(part);
      return true;
    }
    final joined = BytesBuilder(copy: false);
    for (var i = 0; i < seqLen; i++) {
      joined.add(_simple[i]!);
    }
    final whole = Uint8List.sublistView(joined.takeBytes(), 0, _messageLen);
    if (crc32(whole) != _checksum) return false;
    message = Uint8List.fromList(whole);
    return true;
  }

  void _addMixed(_Mixed part) {
    if (_mixed.containsKey(part.key)) return;
    var reduced = part;
    for (final index in part.indexes) {
      if (_simple[index] case final data?) {
        reduced = reduced.reducedBy(_Mixed({index}, data));
      }
    }
    for (final other in _mixed.values) {
      reduced = reduced.reducedBy(other);
    }
    if (reduced.simple) {
      _queue.add(reduced);
    } else {
      _reduceMixedBy(reduced);
      _mixed[reduced.key] = reduced;
    }
  }

  void _reduceMixedBy(_Mixed part) {
    final mixed = <String, _Mixed>{};
    for (final other in _mixed.values) {
      final reduced = other.reducedBy(part);
      if (reduced.simple) {
        _queue.add(reduced);
      } else {
        mixed[reduced.key] = reduced;
      }
    }
    _mixed = mixed;
  }

  /// bc-ur's choose_fragments: part n of m is fragment n - 1 while n <= m,
  /// and after that a mix the sender chose at random, from a generator both
  /// sides seed the same way.
  Set<int> _fragments(_Part part) {
    if (part.seqNum <= seqLen) return {part.seqNum - 1};
    final random = Xoshiro256([
      ..._bigEndian32(part.seqNum),
      ..._bigEndian32(part.checksum),
    ]);
    final degrees = _degrees ??= _Sampler([
      for (var i = 1; i <= seqLen; i++) 1.0 / i,
    ]);
    final degree = degrees.next(random) + 1;
    // bc-ur shuffles all the fragments and takes the first [degree]; the
    // rest of the shuffle draws nothing that changes those.
    return shuffled(
      List.generate(seqLen, (i) => i),
      random,
      count: degree,
    ).toSet();
  }
}

List<int> _bigEndian32(int n) => [
  (n >> 24) & 0xFF,
  (n >> 16) & 0xFF,
  (n >> 8) & 0xFF,
  n & 0xFF,
];

/// The first [count] (all, without it) of [items] in a random order drawn
/// from [random], as bc-ur's shuffled does.
@visibleForTesting
List<T> shuffled<T>(List<T> items, Xoshiro256 random, {int? count}) {
  final remaining = List.of(items);
  final result = <T>[];
  while (remaining.isNotEmpty && result.length < (count ?? items.length)) {
    result.add(remaining.removeAt(random.nextInt(0, remaining.length - 1)));
  }
  return result;
}

/// Vose's alias method, as bc-ur's RandomSampler does it: picks i with a
/// chance in proportion to the i-th weight. Every step is bc-ur's, in its
/// order, so both sides pick the same.
class _Sampler {
  _Sampler(List<double> weights) {
    final n = weights.length;
    var sum = 0.0;
    for (final weight in weights) {
      sum += weight;
    }
    final p = [for (final weight in weights) weight * n / sum];
    final small = <int>[];
    final large = <int>[];
    for (var i = n - 1; i >= 0; i--) {
      (p[i] < 1 ? small : large).add(i);
    }
    _probs = List.filled(n, 0.0);
    _aliases = List.filled(n, 0);
    while (small.isNotEmpty && large.isNotEmpty) {
      final a = small.removeLast();
      final g = large.removeLast();
      _probs[a] = p[a];
      _aliases[a] = g;
      p[g] += p[a] - 1;
      (p[g] < 1 ? small : large).add(g);
    }
    while (large.isNotEmpty) {
      _probs[large.removeLast()] = 1;
    }
    while (small.isNotEmpty) {
      _probs[small.removeLast()] = 1;
    }
  }

  late final List<double> _probs;
  late final List<int> _aliases;

  int next(Xoshiro256 random) {
    final r1 = random.nextDouble();
    final r2 = random.nextDouble();
    final i = (_probs.length * r1).toInt();
    return r2 < _probs[i] ? i : _aliases[i];
  }
}

/// The xoshiro256** 1.0 generator (David Blackman and Sebastiano Vigna, public
/// domain), seeded as bc-ur seeds it: from the SHA-256 of [seed]. Dart's ints
/// are 64-bit and wrap around like C's unsigned ones; only the shift right
/// has to be the unsigned >>>.
@visibleForTesting
class Xoshiro256 {
  Xoshiro256(List<int> seed) {
    final digest = sha256(seed);
    for (var i = 0; i < 4; i++) {
      var v = 0;
      for (var n = 0; n < 8; n++) {
        v = (v << 8) | digest[i * 8 + n];
      }
      _s[i] = v;
    }
  }

  final _s = List<int>.filled(4, 0);

  static int _rotl(int x, int k) => (x << k) | (x >>> (64 - k));

  /// The next 64 bits, as Dart's signed int.
  int next() {
    final s = _s;
    final result = _rotl(s[1] * 5, 7) * 9;
    final t = s[1] << 17;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = _rotl(s[3], 45);
    return result;
  }

  /// In [0, 1): the next 64 bits as an unsigned number, rounded to a double
  /// as C++ rounds one, over 2^64.
  double nextDouble() {
    final n = next();
    if (n >= 0) return n.toDouble() / 18446744073709551616.0;
    // From 2^63 up, doubles are 2^11 apart: round to the nearest, ties to
    // even.
    var high = n >>> 11;
    final low = n & 0x7FF;
    if (low > 0x400 || (low == 0x400 && high.isOdd)) high++;
    return high * 2048.0 / 18446744073709551616.0;
  }

  /// From [low] to [high], both included.
  int nextInt(int low, int high) =>
      (nextDouble() * (high - low + 1)).toInt() + low;
}

/// bc-ur's minimal bytewords: each byte as the first and last letter of its
/// word, with the CRC-32 of the bytes after them. Null if [text] isn't that,
/// or its CRC-32 doesn't match.
Uint8List? _fromBytewords(String text) {
  if (text.length.isOdd || text.length < 10) return null;
  final bytes = Uint8List(text.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final x = text.codeUnitAt(2 * i) - 0x61;
    final y = text.codeUnitAt(2 * i + 1) - 0x61;
    if (x < 0 || x >= 26 || y < 0 || y >= 26) return null;
    final byte = _byteOfWord[y * 26 + x];
    if (byte < 0) return null;
    bytes[i] = byte;
  }
  final body = Uint8List.sublistView(bytes, 0, bytes.length - 4);
  final crc = crc32(body);
  for (var i = 0; i < 4; i++) {
    if (bytes[body.length + i] != (crc >> (24 - 8 * i)) & 0xFF) return null;
  }
  return Uint8List.fromList(body);
}

/// [body] in minimal bytewords, with its CRC-32.
@visibleForTesting
String toBytewords(List<int> body) {
  final out = StringBuffer();
  for (final byte in [...body, ..._bigEndian32(crc32(body))]) {
    out
      ..write(_words[byte * 4])
      ..write(_words[byte * 4 + 3]);
  }
  return out.toString();
}

/// The 256 bytewords, one per byte. No two share both their first and last
/// letter, which is all the minimal form keeps.
const _words =
    'ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabias'
    'bluebodybragbrewbulbbuzzcalmcashcatschefcityclawcodecolacookcost'
    'cruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdull'
    'dutyeacheasyechoedgeepicevenexamexiteyesfactfairfernfigsfilmfish'
    'fizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirlglow'
    'goodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhope'
    'hornhutsicedideaidleinchinkyintoirisironitemjadejazzjoinjoltjowl'
    'judojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamb'
    'lavalazyleaflegsliarlimplionlistlogoloudloveluaulucklungmainmany'
    'mathmazememomenumeowmildmintmissmonknailnavyneednewsnextnoonnote'
    'numbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolpose'
    'puffpumapurrquadquizraceramprealredorichroadrockroofrubyruinruns'
    'rustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotask'
    'taxitenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuser'
    'vastveryvetovialvibeviewvisavoidvowswallwandwarmwaspwavewaxywebs'
    'whatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom';

/// The byte of each word, by its last and first letter: -1 for no word.
final _byteOfWord = () {
  final table = List<int>.filled(26 * 26, -1);
  for (var i = 0; i < 256; i++) {
    final x = _words.codeUnitAt(i * 4) - 0x61;
    final y = _words.codeUnitAt(i * 4 + 3) - 0x61;
    table[y * 26 + x] = i;
  }
  return table;
}();

/// Reads the little CBOR a UR part is: definite lengths only.
class _Cbor {
  _Cbor(this._bytes);

  final Uint8List _bytes;
  var _at = 0;

  /// The argument of the next item, which must be of [major] type: the value
  /// of an unsigned integer, the length of a byte string, the size of an
  /// array.
  int head(int major) {
    if (_at >= _bytes.length) throw const FormatException('CBOR ends early');
    final first = _bytes[_at++];
    if (first >> 5 != major) throw const FormatException('CBOR type');
    final info = first & 0x1F;
    if (info < 24) return info;
    final length = switch (info) {
      24 => 1,
      25 => 2,
      26 => 4,
      27 => 8,
      _ => throw const FormatException('CBOR length'),
    };
    if (_at + length > _bytes.length) {
      throw const FormatException('CBOR ends early');
    }
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | _bytes[_at++];
    }
    // Past 2^63 a Dart int turns negative: no message is that long.
    if (value < 0) throw const FormatException('CBOR value');
    return value;
  }

  Uint8List byteString() {
    final length = head(2);
    if (length > _bytes.length - _at) {
      throw const FormatException('CBOR ends early');
    }
    return Uint8List.fromList(
      Uint8List.sublistView(_bytes, _at, _at += length),
    );
  }
}

/// CRC-32 (the one zlib and PNG use), which UR codes check their parts and
/// messages with.
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = (crc >>> 8) ^ _crcTable[(crc ^ byte) & 0xFF];
  }
  return crc ^ 0xFFFFFFFF;
}

final _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var j = 0; j < 8; j++) {
    c = c.isEven ? c >>> 1 : 0xEDB88320 ^ (c >>> 1);
  }
  return c;
});

/// SHA-256 (FIPS 180-4) of [message]. bc-ur seeds the generator that picks a
/// fountain part's fragments with it; nothing here relies on it for secrecy.
Uint8List sha256(List<int> message) {
  final length = message.length;
  final padded = Uint8List((length + 9 + 63) ~/ 64 * 64)
    ..setAll(0, message)
    ..[length] = 0x80;
  final bits = length * 8;
  for (var i = 0; i < 8; i++) {
    padded[padded.length - 1 - i] = (bits >>> (8 * i)) & 0xFF;
  }
  const mask = 0xFFFFFFFF;
  int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & mask;
  final h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < padded.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final at = chunk + 4 * i;
      w[i] =
          padded[at] << 24 |
          padded[at + 1] << 16 |
          padded[at + 2] << 8 |
          padded[at + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & mask;
    }
    var [a, b, c, d, e, f, g, hh] = h;
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final choice = (e & f) ^ (~e & g);
      final t1 = (hh + s1 + choice + _k[i] + w[i]) & mask;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + majority) & mask;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }
    for (final (i, v) in [a, b, c, d, e, f, g, hh].indexed) {
      h[i] = (h[i] + v) & mask;
    }
  }
  return Uint8List.fromList([
    for (final v in h) ...[
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ],
  ]);
}

const _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];
