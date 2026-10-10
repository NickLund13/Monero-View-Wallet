/// Settings → Open-source licenses: Flutter's license list, plus the app's own
/// license and the code and fonts the app bundles that Flutter doesn't know
/// about.
///
/// Flutter lists its engine and every Dart package by itself. The native
/// libraries (the wallet library and Tor), the Java and Kotlin libraries of
/// the Android build and the fonts come from elsewhere, so their licenses are
/// kept in assets/licenses/ and added here.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

/// The builds of the app. The list shows only the licenses of what the
/// running build ships (anything else, such as the tests, shows them all).
enum Build {
  iPhone,
  windows,
  android;

  /// The build that is running, or null for anything else.
  static Build? get running => Platform.isIOS
      ? iPhone
      : Platform.isWindows
      ? windows
      : Platform.isAndroid
      ? android
      : null;
}

/// In every build.
const allBuilds = {Build.iPhone, Build.windows, Build.android};

/// In the builds that have Tor in them.
const buildsWithTor = {Build.iPhone, Build.windows, Build.android};

/// The app as the license list names it.
const appName = 'Monero View Wallet';

/// The app's own notice at the top of the license list, as GPL-3.0 section
/// 5(d) asks of an interactive program: who holds the copyright, that it is
/// free software without warranty, and where its license is.
const appLegalese =
    'Copyright (C) 2026 NickLund13 and the Monero View Wallet contributors\n\n'
    'Free software under the GNU GPL version 3, with an App Store '
    'permission, and without any warranty. The license is under '
    '$appName below.';

/// Each license file in assets/licenses/, the parts of the app it covers as
/// the license list names them, and the builds it is in.
/// docs/third-party-code.md says which version of each is inside and where
/// each text comes from.
const bundledLicenses = <(List<String>, String, Set<Build>)>[
  // The app's own code: APP-STORE-PERMISSION.txt and LICENSE in the repository.
  ([appName], 'monero-view.txt', allBuilds),
  ([appName], 'gpl-3.0.txt', allBuilds),
  // The wallet library, monero_c, and what is built into it.
  (['Monero'], 'monero.txt', allBuilds),
  (['epee'], 'epee.txt', allBuilds),
  (['LMDB'], 'lmdb.txt', allBuilds),
  (['Easylogging++'], 'easylogging.txt', allBuilds),
  (['RandomX'], 'randomx.txt', allBuilds),
  (['RapidJSON'], 'rapidjson.txt', allBuilds),
  (['monero_c', 'polyseed', 'trezor-common'], 'lgpl-source.txt', allBuilds),
  (['monero_c'], 'monero_c.txt', allBuilds),
  (['polyseed'], 'polyseed.txt', allBuilds),
  (['trezor-common'], 'trezor-common.txt', allBuilds),
  (['monero_c', 'polyseed', 'trezor-common'], 'gpl-3.0.txt', allBuilds),
  (['utf8proc'], 'utf8proc.txt', allBuilds),
  // Also the app's own reader of animated QR codes, lib/ur.dart, a port of
  // bc-ur's decoder.
  (['bc-ur'], 'bc-ur.txt', allBuilds),
  (['Boost'], 'boost.txt', allBuilds),
  (['OpenSSL'], 'openssl.txt', allBuilds),
  (['libsodium'], 'libsodium.txt', allBuilds),
  (['Unbound'], 'unbound.txt', allBuilds),
  (['Protocol Buffers'], 'protobuf.txt', allBuilds),
  // The runtime the Windows wallet library was built with.
  (['MinGW-w64 runtime'], 'mingw-w64-runtime.txt', {Build.windows}),
  (['winpthreads'], 'winpthreads.txt', {Build.windows}),
  (['GCC runtime'], 'gcc-runtime-library-exception.txt', {Build.windows}),
  (['GCC runtime'], 'gpl-3.0.txt', {Build.windows}),
  // Tor and the libraries built into it (OpenSSL is listed above).
  (['Tor'], 'tor.txt', buildsWithTor),
  // The Windows and Android tor is the Tor Project's GPL build.
  (['Tor'], 'tor-source.txt', {Build.windows, Build.android}),
  (['Tor'], 'gpl-3.0.txt', {Build.windows, Build.android}),
  (['libevent'], 'libevent.txt', buildsWithTor),
  (['liblzma'], 'liblzma.txt', {Build.iPhone}),
  (['Tor.framework'], 'tor-framework.txt', {Build.iPhone}),
  (['zlib'], 'zlib.txt', {Build.windows, Build.android}),
  (['Zstandard'], 'zstd.txt', {Build.android}),
  // The Java and Kotlin libraries that Flutter's Android code brings along,
  // and the camera and the QR code reader of the app's own.
  (
    [
      'AndroidX',
      'Kotlin',
      'kotlinx.coroutines',
      'kotlinx.atomicfu',
      'JetBrains Java Annotations',
      'Guava ListenableFuture',
      'ReLinker',
      'JSpecify',
      'Dagger',
      'Jakarta Dependency Injection',
      'javax.inject',
      'AutoValue',
      'ZXing',
    ],
    'android-libraries.txt',
    {Build.android},
  ),
  // The fonts.
  (['IBM Plex Sans', 'IBM Plex Mono'], 'ibm-plex.txt', allBuilds),
];

/// Adds the [bundledLicenses] of this build to the list Settings shows. Call
/// once, at launch. The files are read only when the list is opened.
void addBundledLicenses() {
  final running = Build.running;
  LicenseRegistry.addLicense(() async* {
    for (final (packages, file, builds) in bundledLicenses) {
      if (running != null && !builds.contains(running)) continue;
      yield LicenseEntryWithLineBreaks(
        packages,
        await rootBundle.loadString('assets/licenses/$file'),
      );
    }
  });
}

/// The row in Settings that opens the license list.
class LicensesRow extends StatelessWidget {
  const LicensesRow({super.key});

  @override
  Widget build(BuildContext context) => NavRow(
    'Open-source licenses',
    onTap: () => showLicensePage(
      context: context,
      applicationName: appName,
      applicationLegalese: appLegalese,
    ),
  );
}
