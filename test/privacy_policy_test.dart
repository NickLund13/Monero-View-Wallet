// The privacy policy: the app shows docs/privacy-policy.md, the page App Store
// Connect links to, word for word, and Setup and Settings open it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/privacy_policy.dart';
import 'package:monero_view_wallet/setup_screen.dart';
import 'package:monero_view_wallet/ui.dart';

void main() {
  test('the app shows the same policy as docs/privacy-policy.md', () {
    expect(
      privacyPolicy,
      File('docs/privacy-policy.md').readAsStringSync().replaceAll('\r', ''),
      reason:
          'Copy docs/privacy-policy.md into privacyPolicy in '
          'lib/privacy_policy.dart.',
    );
  });

  test('reads the Markdown the policy uses', () {
    expect(
      policyBlocks(
        '# Title\n\nOne line\nand the next.\n\n## Heading\n### Sub\n'
        'A **bold** word.\n\n- An item\n  that wraps.\n- Another.\n',
      ),
      [
        (Block.title, 'Title'),
        (Block.paragraph, 'One line and the next.'),
        (Block.heading, 'Heading'),
        (Block.subheading, 'Sub'),
        (Block.paragraph, 'A **bold** word.'),
        (Block.item, 'An item that wraps.'),
        (Block.item, 'Another.'),
      ],
    );
  });

  test('the policy uses no Markdown the app would show as it is', () {
    final blocks = policyBlocks(privacyPolicy);
    expect(blocks.first, (Block.title, 'Monero View privacy policy'));
    expect(blocks.where((b) => b.$1 == Block.title), hasLength(1));
    for (final (_, text) in blocks) {
      expect('**'.allMatches(text).length.isEven, isTrue, reason: text);
      // Links, code, emphasis with _ or a single *, numbered lists, HTML,
      // and backslash escapes, which the web page would drop the backslash
      // of but the app would show.
      expect(
        text,
        isNot(
          contains(RegExp(r'\]\(|`|(^|\s)[_*]\w|^\d+\. |<|\\[!-/:-@\[-`{-~]')),
        ),
        reason: text,
      );
    }
  });

  testWidgets('Setup and the Settings row open the policy', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.scrollUntilVisible(
      find.text('Privacy policy'),
      100,
      // The screen's list, not one of the text fields inside it.
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsOne);
    expect(find.text('What the app keeps on your iPhone'), findsOne);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsNothing);
    expect(find.byType(SetupScreen), findsOne);

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(body: PrivacyPolicyRow()),
      ),
    );
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsOne);
  });
}
