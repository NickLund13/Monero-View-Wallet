/// Keeps seeds and private keys out of the app's free-text fields (SECURITY.md
/// rule 2). A wallet name, a subaddress label or a node is never one, so a
/// paste that looks like one is refused whole instead of being kept.
library;

import 'package:flutter/services.dart';

/// What Setup and the fields below say when they refuse a seed or a key.
const neverEnterSeed =
    'Never enter your 25-word seed or spend key. '
    "This app only watches; it can't send funds.";

/// 12 or more words in a row, in any script: what a seed phrase looks like
/// (BIP39 12 to 24 words, Polyseed 16, Monero's own 25).
final _wordRun = RegExp(r'(?:\p{L}+[\s,;+]+){11,}\p{L}+', unicode: true);

/// 64 hex characters in a row: what a private key looks like.
final _hexKey = RegExp(r'[0-9a-fA-F]{64}');

/// True if [text] holds what looks like a seed phrase or a private key.
bool looksLikeSecret(String text) =>
    _wordRun.hasMatch(text) || _hexKey.hasMatch(text);

/// True if the edit from [oldValue] to [newValue] put more than one
/// character in at once, as a paste does. Typing adds one at a time.
bool pastedIn(TextEditingValue oldValue, TextEditingValue newValue) {
  final selection = oldValue.selection;
  final replaced = selection.isValid
      ? (selection.end - selection.start).abs()
      : 0;
  return newValue.text.length - (oldValue.text.length - replaced) > 1;
}

/// Refuses an edit that pastes a seed phrase or a private key into the field,
/// and calls [onRefused]: the field stays as it was. Typing is never refused.
class RefuseSecrets extends TextInputFormatter {
  RefuseSecrets(this.onRefused);

  final VoidCallback onRefused;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (pastedIn(oldValue, newValue) && looksLikeSecret(newValue.text)) {
      onRefused();
      return oldValue;
    }
    return newValue;
  }
}
