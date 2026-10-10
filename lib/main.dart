// The view-only wallet, for a real (mainnet) wallet or a stagenet test wallet:
// the first-run flow, then Home on every later launch. Screens follow
// docs/design/DESIGN.md.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_keystore.dart';
import 'home_screen.dart';
import 'keychain.dart';
import 'licenses.dart';
import 'lock.dart';
import 'pick_file.dart';
import 'price.dart';
import 'scan_screen.dart';
import 'secret_store.dart';
import 'session.dart';
import 'setup_screen.dart';
import 'tor.dart';
import 'ui.dart';
import 'wallet.dart';

Future<void> main() async {
  // The lock asks the iPhone what it unlocks with before the first frame.
  WidgetsFlutterBinding.ensureInitialized();
  addBundledLicenses();
  final folder = await keepOnDevice();
  // Before the price lookup starts again: opening the wallet sets torProxy,
  // so with Tor on even the first price request goes through Tor.
  final wallet = ViewWallet.openSaved();
  if (folder != null) {
    keepShowUsd(
      File('$folder${Platform.pathSeparator}show_usd'),
      hasWallet: wallet != null,
    );
  }
  final session = wallet == null
      ? null
      : (WalletSession(wallet)..startPolling());
  // Locked from the first frame, so the balance never shows before Face ID.
  await appLock.start(on: session?.lockOn ?? false);
  // Setup can scan the wallet's QR code with the phone's camera.
  if (Platform.isIOS || Platform.isAndroid) qrCamera = PhoneQrCamera();
  runApp(
    MainApp(
      home: session == null
          ? SetupScreen(lostSaved: ViewWallet.savedButUnreadable)
          : HomeScreen(session),
    ),
  );
  // Key images files opened with the app go to Import key images.
  if (Platform.isIOS) receiveKeyImagesFiles();
}

/// Points the app at this device's folder and secure storage, so the wallet
/// and the Appearance choice are kept between launches. Returns the folder,
/// or null where nothing is kept.
Future<String?> keepOnDevice() async {
  if (Platform.isAndroid) return _keepOnAndroid();
  if (Platform.isWindows) {
    // Without it the files would land wherever the app was started from.
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    if (local.isEmpty) return null;
    final folder = '$local\\MoneroViewWallet';
    walletFile = '$folder\\wallet';
    keepAppearance(File('$folder\\appearance'));
    // tor.exe sits next to the app (windows/CMakeLists.txt puts it there).
    torProgram = '${File(Platform.resolvedExecutable).parent.path}\\tor.exe';
    torFolder = '$folder\\tor';
    return folder;
  }
  if (!Platform.isIOS) return null;
  // The app's own folder, which no other app can read. Dart sees no
  // environment variables on iOS, so not from HOME: iOS puts the temporary
  // folder at the top of it.
  final home = Directory.systemTemp.parent.path;
  final folder = '$home/Library/Application Support/MoneroViewWallet';
  // Out of iCloud and computer backups: the wallet's password never leaves
  // this iPhone, so a backup of the files could never be opened. The same for
  // wallet2's ring database (see the README), if iOS lets it be made.
  final rings = ringDatabase = '$home/.shared-ringdb';
  for (final keep in [folder, rings]) {
    try {
      Directory(keep).createSync(recursive: true);
      excludeFromBackup(keep);
    } on FileSystemException {
      // Without the folder, setup says the wallet can't be saved. Without the
      // ring database, wallet2 does without it.
    }
  }
  walletFile = '$folder/wallet';
  secretStore = const Keychain();
  keepAppearance(File('$folder/appearance'));
  // Tor runs inside the app (ios/Runner/InAppTor.swift) and keeps what it
  // knows of the Tor network among the app's caches, which are never backed
  // up and which iOS may clear: Tor then fetches it again.
  torInApp = true;
  torFolder = '$home/Library/Caches/tor';
  return folder;
}

/// On Android: the app's own folder that Android never backs up, nor moves to
/// a new phone (android/app/src/main/AndroidManifest.xml). The Runner sets it
/// as HOME (MainActivity.kt), so wallet2 keeps its ring database in it too.
/// The password is in the Keystore.
Future<String?> _keepOnAndroid() async {
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty || home == '/') return null;
  secretStore = await AndroidKeystore.open();
  final folder = '$home/MoneroViewWallet';
  ringDatabase = '$home/.shared-ringdb';
  walletFile = '$folder/wallet';
  keepAppearance(File('$folder/appearance'));
  // The Tor Project's tor ships with the app as libtor.so, since Android
  // runs a program only from the app's native library folder, which the
  // Runner names (MainActivity.kt). It keeps what it knows of the Tor network
  // in the same folder as the wallet, which Android never backs up.
  final tor = Platform.environment[torProgramVariable] ?? '';
  if (tor.isNotEmpty) {
    torProgram = tor;
    torFolder = '$home/tor';
  }
  return folder;
}

/// Keeps the Appearance choice in [file] between launches. It and the Show USD
/// value choice are all the app stores as plain text: "system", "light" or
/// "dark" says nothing about the wallet. Returns the listener it adds to
/// [appearance], so a test can take it off again.
VoidCallback keepAppearance(File file) {
  if (file.existsSync()) {
    final saved = file.readAsStringSync();
    appearance.value = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
  }
  void save() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(appearance.value.name);
  }

  appearance.addListener(save);
  return save;
}

/// Keeps the Settings → Show USD value choice in [file] between launches, as
/// "on" or "off", which says nothing about the wallet. A saved "on" starts the
/// price lookup again at launch, but only with a wallet to show a value for:
/// without one Settings can't be reached to turn it off, so the choice goes
/// back to off. A missing file, or one that says anything else, is off.
/// Returns the listener it adds to [usdPrice], so a test can take it off
/// again.
VoidCallback keepShowUsd(File file, {required bool hasWallet}) {
  var saved = file.existsSync() && file.readAsStringSync() == 'on';
  void save() {
    // usdPrice also tells its listeners about each price.
    if (usdPrice.on == saved) return;
    saved = usdPrice.on;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(saved ? 'on' : 'off');
  }

  usdPrice.addListener(save);
  usdPrice.on = saved && hasWallet;
  save();
  return save;
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.home = const SetupScreen()});

  /// The first screen: Setup, unless a test starts elsewhere.
  final Widget home;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appearance,
    builder: (context, mode, _) => MaterialApp(
      title: 'Monero View Wallet',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        // Status bar icons that stay readable on either background.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          // The design is for a phone: keep its width in the Windows test
          // build.
          child: ColoredBox(
            color: context.colors.bg,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: LockGate(child: child!),
              ),
            ),
          ),
        );
      },
      home: home,
    ),
  );
}
