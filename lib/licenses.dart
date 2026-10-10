/// Settings → Open-source licenses: Flutter's license list, plus the app's own
/// license and the code and fonts the app bundles that Flutter doesn't know
/// about.
///
/// Flutter lists its engine and every Dart package by itself. The native
/// libraries (the wallet library and Tor) and the fonts come from elsewhere,
/// so their licenses are kept in assets/licenses/ and added here.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

/// Which build a license is shipped in. The list shows only those in the
/// running build: iPhone or Windows (anything else, such as the tests, shows
/// them all).
enum Build {
  both,
  iPhone,
  windows;

  bool get here => switch (this) {
    both => true,
    iPhone => Platform.isIOS || !Platform.isWindows,
    windows => Platform.isWindows || !Platform.isIOS,
  };
}

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
/// the license list names them, and the build it is in.
/// docs/third-party-code.md says which version of each is inside and where
/// each text comes from.
const bundledLicenses = <(List<String>, String, Build)>[
  // The app's own code: APP-STORE-PERMISSION.txt and LICENSE in the repository.
  ([appName], 'monero-view.txt', Build.both),
  ([appName], 'gpl-3.0.txt', Build.both),
  // The wallet library, monero_c, and what is built into it.
  (['Monero'], 'monero.txt', Build.both),
  (['epee'], 'epee.txt', Build.both),
  (['LMDB'], 'lmdb.txt', Build.both),
  (['Easylogging++'], 'easylogging.txt', Build.both),
  (['RandomX'], 'randomx.txt', Build.both),
  (['RapidJSON'], 'rapidjson.txt', Build.both),
  (['monero_c', 'polyseed', 'trezor-common'], 'lgpl-source.txt', Build.both),
  (['monero_c'], 'monero_c.txt', Build.both),
  (['polyseed'], 'polyseed.txt', Build.both),
  (['trezor-common'], 'trezor-common.txt', Build.both),
  (['monero_c', 'polyseed', 'trezor-common'], 'gpl-3.0.txt', Build.both),
  (['utf8proc'], 'utf8proc.txt', Build.both),
  // Also the app's own reader of animated QR codes, lib/ur.dart, a port of
  // bc-ur's decoder.
  (['bc-ur'], 'bc-ur.txt', Build.both),
  (['Boost'], 'boost.txt', Build.both),
  (['OpenSSL'], 'openssl.txt', Build.both),
  (['libsodium'], 'libsodium.txt', Build.both),
  (['Unbound'], 'unbound.txt', Build.both),
  (['Protocol Buffers'], 'protobuf.txt', Build.both),
  // The runtime the Windows wallet library was built with.
  (['MinGW-w64 runtime'], 'mingw-w64-runtime.txt', Build.windows),
  (['winpthreads'], 'winpthreads.txt', Build.windows),
  (['GCC runtime'], 'gcc-runtime-library-exception.txt', Build.windows),
  (['GCC runtime'], 'gpl-3.0.txt', Build.windows),
  // Tor and the libraries built into it (OpenSSL is listed above).
  (['Tor'], 'tor.txt', Build.both),
  // The Windows tor.exe is the Tor Project's GPL build.
  (['Tor'], 'tor-source.txt', Build.windows),
  (['Tor'], 'gpl-3.0.txt', Build.windows),
  (['libevent'], 'libevent.txt', Build.both),
  (['liblzma'], 'liblzma.txt', Build.iPhone),
  (['Tor.framework'], 'tor-framework.txt', Build.iPhone),
  (['zlib'], 'zlib.txt', Build.windows),
  // The fonts.
  (['IBM Plex Sans', 'IBM Plex Mono'], 'ibm-plex.txt', Build.both),
];

/// Adds the [bundledLicenses] of this build to the list Settings shows. Call
/// once, at launch. The files are read only when the list is opened.
void addBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (packages, file, build) in bundledLicenses) {
      if (!build.here) continue;
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
