// The design's colors, checked without the wallet library.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/ui.dart';

/// WCAG contrast ratio of two opaque colors.
double contrast(Color a, Color b) {
  final (hi, lo) = (a.computeLuminance(), b.computeLuminance());
  return hi > lo ? (hi + 0.05) / (lo + 0.05) : (lo + 0.05) / (hi + 0.05);
}

void main() {
  for (final (name, c) in [
    ('dark', AppColors.dark),
    ('light', AppColors.light),
  ]) {
    test('$name text meets 4.5:1 where it is used', () {
      final onBackgrounds = {
        'text': c.text,
        'sec': c.sec,
        'muted': c.muted,
        'accentText': c.accentText,
        'link': c.link,
        'green': c.green,
        'red': c.red,
      };
      for (final MapEntry(key: token, value: color) in onBackgrounds.entries) {
        for (final (bgName, bg) in [('bg', c.bg), ('card', c.card)]) {
          expect(
            contrast(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$token on $bgName',
          );
        }
      }
      final pairs = {
        'noteText on noteBg': (c.noteText, c.noteBg),
        'accentText on noteBg': (c.accentText, c.noteBg),
        'text on seg': (c.text, c.seg),
        'muted on btn2': (c.muted, c.btn2),
        'green on btn2': (c.green, c.btn2),
        'onAccent on accent': (AppColors.onAccent, AppColors.accent),
      };
      for (final MapEntry(key: what, value: (fg, bg)) in pairs.entries) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: what);
      }
    });

    test('$name warning icons meet 3:1', () {
      expect(contrast(c.amber, c.bg), greaterThanOrEqualTo(3));
      expect(contrast(c.amber, c.noteBg), greaterThanOrEqualTo(3));
    });
  }

  test('light orange text is the accent × 0.72', () {
    int dim(double channel) => (channel * 255 * 0.72).round();
    const a = AppColors.accent;
    expect(
      AppColors.light.accentText,
      Color.fromARGB(255, dim(a.r), dim(a.g), dim(a.b)),
    );
    expect(AppColors.dark.accentText, AppColors.accent);
  });
}
