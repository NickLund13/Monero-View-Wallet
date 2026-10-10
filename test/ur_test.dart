// The animated QR code reader (lib/ur.dart), against the test vectors
// published with bc-ur, the reference code it is ported from, in the version
// the wallet library is built with:
// https://github.com/MrCyjaneK/bc-ur/blob/d82e7c753e710b8000706dc3383b498438795208/test/test.cpp
// The messages there are random bytes made from the seed "Wolf", not wallet
// data.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/ur.dart';

/// bc-ur's make_message: [length] bytes from the generator seeded with [seed].
Uint8List makeMessage(int length, [String seed = 'Wolf']) {
  final random = Xoshiro256(utf8.encode(seed));
  return Uint8List.fromList([
    for (var i = 0; i < length; i++) random.nextInt(0, 255),
  ]);
}

/// bc-ur's make_message_ur: the message as a CBOR byte string.
Uint8List makeMessageCbor(int length) {
  final message = makeMessage(length);
  return Uint8List.fromList([
    if (length < 24)
      0x40 + length
    else if (length < 256) ...[
      0x58,
      length,
    ] else ...[
      0x59,
      length >> 8,
      length & 0xFF,
    ],
    ...message,
  ]);
}

String hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// test_ur_encoder: the first 20 parts of make_message_ur(256), 30 bytes per
/// fragment. Parts 1 to 9 are the fragments, 10 to 20 mix them.
const wolfParts = [
  'ur:bytes/1-9/lpadascfadaxcywenbpljkhdcahkadaemejtswhhylkepmykhhtsytsnoyoyaxaedsuttydmmhhpktpmsrjtdkgslpgh',
  'ur:bytes/2-9/lpaoascfadaxcywenbpljkhdcagwdpfnsboxgwlbaawzuefywkdplrsrjynbvygabwjldapfcsgmghhkhstlrdcxaefz',
  'ur:bytes/3-9/lpaxascfadaxcywenbpljkhdcahelbknlkuejnbadmssfhfrdpsbiegecpasvssovlgeykssjykklronvsjksopdzmol',
  'ur:bytes/4-9/lpaaascfadaxcywenbpljkhdcasotkhemthydawydtaxneurlkosgwcekonertkbrlwmplssjtammdplolsbrdzcrtas',
  'ur:bytes/5-9/lpahascfadaxcywenbpljkhdcatbbdfmssrkzmcwnezelennjpfzbgmuktrhtejscktelgfpdlrkfyfwdajldejokbwf',
  'ur:bytes/6-9/lpamascfadaxcywenbpljkhdcackjlhkhybssklbwefectpfnbbectrljectpavyrolkzczcpkmwidmwoxkilghdsowp',
  'ur:bytes/7-9/lpatascfadaxcywenbpljkhdcavszmwnjkwtclrtvaynhpahrtoxmwvwatmedibkaegdosftvandiodagdhthtrlnnhy',
  'ur:bytes/8-9/lpayascfadaxcywenbpljkhdcadmsponkkbbhgsoltjntegepmttmoonftnbuoiyrehfrtsabzsttorodklubbuyaetk',
  'ur:bytes/9-9/lpasascfadaxcywenbpljkhdcajskecpmdckihdyhphfotjojtfmlnwmadspaxrkytbztpbauotbgtgtaeaevtgavtny',
  'ur:bytes/10-9/lpbkascfadaxcywenbpljkhdcahkadaemejtswhhylkepmykhhtsytsnoyoyaxaedsuttydmmhhpktpmsrjtwdkiplzs',
  'ur:bytes/11-9/lpbdascfadaxcywenbpljkhdcahelbknlkuejnbadmssfhfrdpsbiegecpasvssovlgeykssjykklronvsjkvetiiapk',
  'ur:bytes/12-9/lpbnascfadaxcywenbpljkhdcarllaluzmdmgstospeyiefmwejlwtpedamktksrvlcygmzemovovllarodtmtbnptrs',
  'ur:bytes/13-9/lpbtascfadaxcywenbpljkhdcamtkgtpknghchchyketwsvwgwfdhpgmgtylctotzopdrpayoschcmhplffziachrfgd',
  'ur:bytes/14-9/lpbaascfadaxcywenbpljkhdcapazewnvonnvdnsbyleynwtnsjkjndeoldydkbkdslgjkbbkortbelomueekgvstegt',
  'ur:bytes/15-9/lpbsascfadaxcywenbpljkhdcaynmhpddpzmversbdqdfyrehnqzlugmjzmnmtwmrouohtstgsbsahpawkditkckynwt',
  'ur:bytes/16-9/lpbeascfadaxcywenbpljkhdcawygekobamwtlihsnpalnsghenskkiynthdzotsimtojetprsttmukirlrsbtamjtpd',
  'ur:bytes/17-9/lpbyascfadaxcywenbpljkhdcamklgftaxykpewyrtqzhydntpnytyisincxmhtbceaykolduortotiaiaiafhiaoyce',
  'ur:bytes/18-9/lpbgascfadaxcywenbpljkhdcahkadaemejtswhhylkepmykhhtsytsnoyoyaxaedsuttydmmhhpktpmsrjtntwkbkwy',
  'ur:bytes/19-9/lpbwascfadaxcywenbpljkhdcadekicpaajootjzpsdrbalpeywllbdsnbinaerkurspbncxgslgftvtsrjtksplcpeo',
  'ur:bytes/20-9/lpbbascfadaxcywenbpljkhdcayapmrleeleaxpasfrtrdkncffwjyjzgyetdmlewtkpktgllepfrltataztksmhkbot',
];

void main() {
  test('checksums as bc-ur does', () {
    expect(crc32(utf8.encode('Hello, world!')).toRadixString(16), 'ebe6c6e6');
    expect(crc32(utf8.encode('Wolf')).toRadixString(16), '598c84dc');
    // FIPS 180-2, appendix B: one block and two.
    expect(
      hex(sha256(utf8.encode('abc'))),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      hex(
        sha256(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  test("draws the same numbers as bc-ur's generator", () {
    final mod100 = BigInt.from(100);
    int unsignedMod100(int n) =>
        (BigInt.from(n).toUnsigned(64) % mod100).toInt();

    final wolf = Xoshiro256(utf8.encode('Wolf'));
    expect(
      [for (var i = 0; i < 100; i++) unsignedMod100(wolf.next())],
      // test_rng_1
      [
        42, 81, 85, 8, 82, 84, 76, 73, 70, 88, 2, 74, 40, 48, 77, 54, 88, 7, //
        5, 88, 37, 25, 82, 13, 69, 59, 30, 39, 11, 82, 19, 99, 45, 87, 30, 15,
        32, 22, 89, 44, 92, 77, 29, 78, 4, 92, 44, 68, 92, 69, 1, 42, 89, 50,
        37, 84, 63, 34, 32, 3, 17, 62, 40, 98, 82, 89, 24, 43, 85, 39, 15, 3,
        99, 29, 20, 42, 27, 10, 85, 66, 50, 35, 69, 70, 70, 74, 30, 13, 72, 54,
        11, 5, 70, 55, 91, 52, 10, 43, 43, 52,
      ],
    );

    final checksum = crc32(utf8.encode('Wolf'));
    final fromChecksum = Xoshiro256([
      checksum >> 24,
      (checksum >> 16) & 0xFF,
      (checksum >> 8) & 0xFF,
      checksum & 0xFF,
    ]);
    expect(
      [for (var i = 0; i < 100; i++) unsignedMod100(fromChecksum.next())],
      // test_rng_2
      [
        88, 44, 94, 74, 0, 99, 7, 77, 68, 35, 47, 78, 19, 21, 50, 15, 42, 36, //
        91, 11, 85, 39, 64, 22, 57, 11, 25, 12, 1, 91, 17, 75, 29, 47, 88, 11,
        68, 58, 27, 65, 21, 54, 47, 54, 73, 83, 23, 58, 75, 27, 26, 15, 60, 36,
        30, 21, 55, 57, 77, 76, 75, 47, 53, 76, 9, 91, 14, 69, 3, 95, 11, 73,
        20, 99, 68, 61, 3, 98, 36, 98, 56, 65, 14, 80, 74, 57, 63, 68, 51, 56,
        24, 39, 53, 80, 57, 51, 81, 3, 1, 30,
      ],
    );

    final ints = Xoshiro256(utf8.encode('Wolf'));
    expect(
      [for (var i = 0; i < 100; i++) ints.nextInt(1, 10)],
      // test_rng_3
      [
        6, 5, 8, 4, 10, 5, 7, 10, 4, 9, 10, 9, 7, 7, 1, 1, 2, 9, 9, 2, 6, 4, //
        5, 7, 8, 5, 4, 2, 3, 8, 7, 4, 5, 1, 10, 9, 3, 10, 2, 6, 8, 5, 7, 9, 3,
        1, 5, 2, 7, 1, 4, 4, 4, 4, 9, 4, 5, 5, 6, 9, 5, 1, 2, 8, 3, 3, 2, 8, 4,
        3, 2, 1, 10, 8, 9, 3, 10, 8, 5, 5, 6, 7, 10, 5, 8, 9, 4, 6, 4, 2, 10,
        2, 1, 7, 9, 6, 7, 4, 2, 5,
      ],
    );

    final shuffles = Xoshiro256(utf8.encode('Wolf'));
    expect(
      [
        for (var i = 0; i < 3; i++)
          shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], shuffles),
      ],
      // The first three of test_shuffle.
      [
        [6, 4, 9, 3, 10, 5, 7, 8, 1, 2],
        [10, 8, 6, 5, 1, 2, 3, 9, 7, 4],
        [6, 4, 5, 8, 9, 3, 2, 1, 7, 10],
      ],
    );

    // test_xor's first bytes.
    expect(hex(makeMessage(10)), '916ec65cf77cadf55cd7');
  });

  test('reads a message that fits in one code', () {
    // test_single_part_ur
    const code =
        'ur:bytes/hdeymejtswhhylkepmykhhtsytsnoyoyaxaedsuttydmmhhpktpmsrjtgwdp'
        'fnsboxgwlbaawzuefywkdplrsrjynbvygabwjldapfcsdwkbrkch';
    expect(urType(code), 'bytes');
    final reader = UrReader('bytes');
    expect(reader.add(code), isTrue);
    expect(reader.complete, isTrue);
    expect(reader.message, makeMessageCbor(50));
    expect(reader.bytes, makeMessage(50));
    expect((reader.partsKnown, reader.partsTotal), (1, 1));
    expect(reader.asOneCode, code);
  });

  test('puts a message sent in parts back together, in any order', () {
    final reader = UrReader('bytes');
    expect((reader.partsKnown, reader.partsTotal), (0, 0));
    for (final part in wolfParts.take(9).toList().reversed) {
      expect(reader.complete, isFalse);
      expect(reader.add(part), isTrue);
    }
    expect(reader.complete, isTrue);
    expect(reader.message, makeMessageCbor(256));
    expect(reader.bytes, makeMessage(256));
    expect((reader.partsKnown, reader.partsTotal), (9, 9));
    // Once complete, it takes nothing more.
    expect(reader.add(wolfParts[10]), isFalse);

    // The whole message as one code reads back the same.
    final again = UrReader('bytes');
    expect(again.add(reader.asOneCode), isTrue);
    expect(again.message, reader.message);
  });

  test('finishes from the mixed parts when fragments were missed', () {
    final reader = UrReader('bytes');
    // Fragments 1, 4 and 8 missed, as when the camera didn't catch them.
    for (final i in [1, 2, 4, 5, 6, 8]) {
      reader.add(wolfParts[i]);
    }
    expect((reader.partsKnown, reader.partsTotal), (6, 9));
    for (final part in wolfParts.skip(9)) {
      if (reader.complete) break;
      reader.add(part);
    }
    expect(reader.complete, isTrue);
    expect(reader.bytes, makeMessage(256));
  });

  test('reads codes in capitals, and passes over repeats and damage', () {
    final reader = UrReader('bytes');
    expect(reader.add(wolfParts[0].toUpperCase()), isTrue);
    expect(reader.add(wolfParts[0]), isFalse, reason: 'already known');
    // One letter changed: the part's checksum no longer matches.
    final damaged = wolfParts[1].replaceRange(30, 31, 'z');
    expect(reader.add(damaged), isFalse);
    // The sequence in the path must agree with the part.
    expect(reader.add(wolfParts[1].replaceFirst('/2-9/', '/3-9/')), isFalse);
    for (final text in [
      '',
      'ur:',
      'ur:bytes',
      'ur:bytes/',
      'ur:bytes/1-9',
      'ur:bytes/0-9/lpadascfadaxcywenbpljkhdcahkadaemejtswhhylkepmykhh',
      'ur:Bytes!/1-9/lpad',
      'monero-wallet:5abc?view_key=00&height=1',
    ]) {
      expect(reader.add(text), isFalse, reason: text);
    }
    expect((reader.partsKnown, reader.partsTotal), (1, 9));
    // Another type is not for this reader.
    expect(UrReader('xmr-keyimage').add(wolfParts[0]), isFalse);
    expect(urType(wolfParts[0]), 'bytes');
    expect(urType('UR:XMR-KEYIMAGE/1-2/ABCD'), 'xmr-keyimage');
    expect(urType('https://example.com/'), isNull);
  });

  test('starts over when a part of another message comes', () {
    final reader = UrReader('bytes');
    reader.add(wolfParts[0]);
    reader.add(wolfParts[1]);
    expect(reader.partsKnown, 2);
    // A part of another message: its sizes and checksum differ, so reading
    // starts over with it.
    expect(reader.add(_otherMessagePart), isTrue);
    expect((reader.partsKnown, reader.partsTotal), (1, 9));
    expect(reader.add(wolfParts[2]), isTrue, reason: 'starts over again');
    expect(reader.partsKnown, 1);
  });
}

/// test_fountain_encoder_cbor's first part: a part of make_message(256)
/// itself rather than of its CBOR, so its sizes and checksum differ from
/// [wolfParts].
final _otherMessagePart =
    'ur:bytes/1-9/${toBytewords(_fromHex('8501091901001a0167aa07581d916ec65cf77cadf55cd7f9cda1a1030026ddd42e905b77adc36e4f2d3c'))}';

List<int> _fromHex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
