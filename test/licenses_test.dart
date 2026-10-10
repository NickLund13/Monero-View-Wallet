// Settings → Open-source licenses: every license file the app bundles is in
// the list, loads, and shows on the license page.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/licenses.dart';
import 'package:monero_view_wallet/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each license file is listed, and each listed one exists', () {
    final onDisk = Directory('assets/licenses')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    final listed = {for (final (_, file, _) in bundledLicenses) file};
    expect(listed, onDisk);
  });

  test('every bundled license loads with its text', () async {
    addBundledLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    // Off iPhone and Windows, as here, the list has every build's licenses.
    for (final (packages, file, _) in bundledLicenses) {
      final text = File('assets/licenses/$file').readAsStringSync();
      expect(text.trim(), isNotEmpty, reason: file);
      expect(text, isNot(contains('\r')), reason: '$file has CRLF');
      expect(
        entries.where(
          (e) =>
              listEquals(e.packages.toList(), packages) &&
              e.paragraphs.isNotEmpty,
        ),
        isNotEmpty,
        reason: '$packages',
      );
    }
  });

  test("the app's own license is the repository's", () {
    expect(
      File('assets/licenses/monero-view.txt').readAsStringSync(),
      File('APP-STORE-PERMISSION.txt').readAsStringSync().replaceAll('\r', ''),
      reason:
          'Copy APP-STORE-PERMISSION.txt to assets/licenses/monero-view.txt.',
    );
    final license = File('LICENSE').readAsStringSync().replaceAll('\r', '');
    expect(
      license,
      startsWith(
        '                    GNU GENERAL PUBLIC LICENSE\n'
        '                       Version 3, 29 June 2007\n',
      ),
    );
    // The copyright line at the top of the list is the notice's.
    expect(
      File('APP-STORE-PERMISSION.txt').readAsStringSync(),
      contains(appLegalese.split('\n').first),
    );
  });

  test("the wallet library's LGPL parts say where their source is", () {
    final note = File('assets/licenses/lgpl-source.txt').readAsStringSync();
    // The same commit as pubspec.yaml and tool/fetch_monero_c.sh.
    const monero = '3bfb3856a838f2bf6b729501837bb0295dedf25d';
    expect(note, contains('monero_c/tree/$monero'));
    expect(File('pubspec.yaml').readAsStringSync(), contains(monero));
    expect(File('tool/fetch_monero_c.sh').readAsStringSync(), contains(monero));
  });

  testWidgets('the Settings row opens the license list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(body: LicensesRow()),
      ),
    );
    await tester.tap(find.text('Open-source licenses'));
    // Not pumpAndSettle: the page shows a spinner while it reads the files.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining('Copyright (C) 2026'), findsOneWidget);
  });
}
