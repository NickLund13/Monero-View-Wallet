// What keeps a seed phrase or a private key out of the wallet's name, a
// subaddress label and the node fields. Every "seed" here is the word "fake"
// over and over, and every "key" is made of zeros.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/secret_guard.dart';

void main() {
  String words(int count, [String separator = ' ']) =>
      List.filled(count, 'fake').join(separator);

  test('knows a seed phrase or a private key when it sees one', () {
    expect(looksLikeSecret(words(12)), isTrue);
    expect(looksLikeSecret(words(25)), isTrue);
    expect(looksLikeSecret(words(16, ', ')), isTrue);
    expect(looksLikeSecret(words(13, '\n')), isTrue);
    expect(looksLikeSecret('My seed: ${words(12)}.'), isTrue);
    // Any script, as Monero's seeds come in many languages.
    expect(looksLikeSecret(List.filled(12, 'фейк').join(' ')), isTrue);
    expect(looksLikeSecret('0' * 64), isTrue);
    expect(looksLikeSecret('key ${'A' * 64} end'), isTrue);

    expect(looksLikeSecret(words(11)), isFalse);
    expect(looksLikeSecret('0' * 63), isFalse);
    expect(looksLikeSecret('Rent from Alex'), isFalse);
    expect(looksLikeSecret('Savings'), isFalse);
    expect(looksLikeSecret('node.example.org:18081'), isFalse);
    expect(looksLikeSecret('${'a' * 56}.onion:18081'), isFalse);
  });

  test('tells a paste from typing', () {
    TextEditingValue value(String text, [TextSelection? selection]) =>
        TextEditingValue(
          text: text,
          selection: selection ?? TextSelection.collapsed(offset: text.length),
        );
    expect(pastedIn(value(''), value('a')), isFalse);
    expect(pastedIn(value('ab'), value('abc')), isFalse);
    expect(pastedIn(value('abc'), value('ab')), isFalse);
    expect(pastedIn(value(''), value('ab')), isTrue);
    expect(pastedIn(value('ab'), value('ab${words(12)}')), isTrue);
    // Typing over a selection replaces it with one character.
    final all = value(
      'abc',
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(pastedIn(all, value('x')), isFalse);
    expect(pastedIn(all, value('xyz')), isTrue);
    expect(
      pastedIn(
        value('abc', const TextSelection(baseOffset: 1, extentOffset: 2)),
        value('aXYc'),
      ),
      isTrue,
    );
  });

  test('refuses a pasted secret whole, and never what is typed', () {
    var refused = 0;
    final guard = RefuseSecrets(() => refused++);
    TextEditingValue value(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

    final before = value('Rent');
    expect(guard.formatEditUpdate(before, value(words(12))), before);
    expect(guard.formatEditUpdate(before, value('Rent ${'0' * 64}')), before);
    expect(refused, 2);

    final label = value('Rent from Alex');
    expect(guard.formatEditUpdate(before, label), label);
    // The twelfth word typed one letter at a time.
    final eleven = value('${words(11)} fak');
    final twelve = value('${words(11)} fake');
    expect(guard.formatEditUpdate(eleven, twelve), twelve);
    expect(refused, 2);
  });
}
