// Not the app: the Android build workflow (.github/workflows/android-build.yml)
// runs this on the Android emulator, as a release build, to check that the
// wallet library is in the app and works on Android, that the wallet is saved
// in the app's own folder with its password in the Keystore, that the
// password is still there when the Keystore is read afresh, as at the next
// launch, that the Tor Project's tor was installed with the app and runs,
// that the camera's native code answers, and that the app draws its first
// screen.
//
// The library is called with obviously fake input (no real address or key).
// The saved wallet is a random throwaway made here, as in the app's tests, and
// deleted again with its password. Only "ok" or the error is printed, each
// line starting "android_smoke: ", and read by tool/android_smoke.sh from the
// emulator's log, together with the names of the files the app keeps and the
// libraries tor says it was built with. Nothing goes to the network: the saved
// wallet's node is 127.0.0.1 port 9, where nothing listens, and tor is only
// asked for its version.

import 'dart:io';

import 'package:flutter/widgets.dart';
// ignore_for_file: implementation_imports, avoid_print
import 'package:monero/src/monero.dart';
import 'package:monero_view_wallet/android_keystore.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/scan_screen.dart';
import 'package:monero_view_wallet/secret_store.dart';
import 'package:monero_view_wallet/tor.dart';
import 'package:monero_view_wallet/wallet.dart';

void report(String line) => print('android_smoke: $line');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  report('wallet library: ${_walletLibrary()}');
  final folder = await keepOnDevice();
  report('folder: ${_folder(folder)}');
  report('keystore: ${await _keystore()}');
  report('saved wallet: ${await _savedWallet()}');
  report('tor: ${await _tor()}');
  report('camera: ${await _camera()}');
  // Names only, to show where the app and wallet2 keep their files.
  final home = Platform.environment['HOME'];
  if (home != null) {
    for (final entry in Directory(home).listSync(recursive: true)) {
      report('file: ${entry.path.substring(home.length)}');
    }
  }
  runApp(const MainApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    report('first frame: ok');
    _cameraView();
  });
}

/// Once tool/android_smoke.sh has allowed the camera, as a person does at the
/// first scan, shows Scan wallet QR for a while, then takes it away again.
/// The script checks that the camera is on while it shows, and off once it
/// has gone. Nothing the camera sees is kept: no code is there to read.
Future<void> _cameraView() async {
  try {
    final camera = qrCamera;
    if (camera == null) return report('camera view: no camera');
    var status = '';
    for (var i = 0; i < 180 && status != 'authorized'; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      status = await PhoneQrCamera.channel.invokeMethod<String>('status') ?? '';
    }
    if (status != 'authorized') return report('camera view: not allowed');
    runApp(MainApp(home: ScanWalletScreen(camera: camera)));
    await Future<void>.delayed(const Duration(seconds: 2));
    report('camera view: shown');
    await Future<void>.delayed(const Duration(seconds: 30));
    runApp(const MainApp());
    await Future<void>.delayed(const Duration(seconds: 2));
    report('camera view: gone');
  } catch (e) {
    report('camera view: failed: $e');
  }
}

/// The tor that ships with the app is where the Runner says (MainActivity.kt),
/// Android may run it, and it is the one tool/fetch_tor.sh pins. The
/// libraries it was built with are reported too, for docs/third-party-code.md.
Future<String> _tor() async {
  try {
    final program = torProgram;
    if (!hasTor || program == null) return 'not in use';
    if (torFolder != '${Platform.environment['HOME']}/tor') {
      return 'unexpected: folder';
    }
    final libraries = await Process.run(program, ['--library-versions']);
    for (final line in '${libraries.stdout}'.split('\n')) {
      if (line.trim().isNotEmpty) report('tor library: ${line.trim()}');
    }
    final version = await Process.run(program, ['--version']);
    final out = '${version.stdout}';
    // "Tor version 0.4.9.13 (git-…)." on Android, without the git part
    // elsewhere.
    return out.startsWith(RegExp(r'Tor version 0\.4\.9\.13[ .]'))
        ? 'ok'
        : 'unexpected: ${out.split('\n').first}';
  } catch (e) {
    return 'failed: $e';
  }
}

/// The camera's native code (QrCamera.kt) answers, without asking for the
/// camera, which nobody on the emulator could allow: the app was just
/// installed, so it may not use it yet. Stopping a camera view that doesn't
/// exist does nothing. Key images by QR keeps the screen on, and lets it
/// sleep again.
Future<String> _camera() async {
  try {
    // As main() does on Android.
    qrCamera = PhoneQrCamera();
    final status = await PhoneQrCamera.channel.invokeMethod<String>('status');
    await PhoneQrCamera.channel.invokeMethod<void>('stop', -1);
    await PhoneQrCamera.channel.invokeMethod<void>('keepScreenOn', true);
    await PhoneQrCamera.channel.invokeMethod<void>('keepScreenOn', false);
    return status == 'notAuthorized' ? 'ok' : 'unexpected: $status';
  } catch (e) {
    return 'failed: $e';
  }
}

/// wallet2 rejecting a made-up address shows the library loaded and ran.
String _walletLibrary() {
  try {
    final problem = ViewWallet.keysProblem(
      address: '5${'1' * 94}',
      viewKey: '0' * 64,
    );
    return problem == 'failed to parse address' ? 'ok' : 'unexpected: $problem';
  } catch (e) {
    return 'failed: $e';
  }
}

/// The app keeps its files in the folder Android never backs up, which the
/// Runner sets as HOME (MainActivity.kt), and wallet2 its ring database
/// there too.
String _folder(String? folder) {
  final home = Platform.environment['HOME'];
  if (home == null || folder == null) return 'not set';
  if (!home.endsWith('/no_backup')) return 'unexpected: not no_backup';
  if (folder != '$home/MoneroViewWallet') return 'unexpected: elsewhere';
  return ringDatabase == '$home/.shared-ringdb' ? 'ok' : 'unexpected: rings';
}

/// The Keystore stores, replaces and deletes a secret, and what it keeps is
/// there when it is read afresh.
Future<String> _keystore() async {
  try {
    final store = secretStore;
    if (store is! AndroidKeystore) return 'not in use';
    const name = 'Monero View Wallet: smoke test';
    store.delete(name);
    if (store.read(name) != null) return 'delete failed';
    for (final secret in ['not a real secret', 'replaced']) {
      if (!store.write(name, secret)) return 'write refused';
      if (store.read(name) != secret) return 'read back wrong';
      // The Keystore's side works through the changes in order, so this
      // reads what the write kept.
      final afresh = await AndroidKeystore.open();
      if (afresh.read(name) != secret) return 'not kept';
    }
    store.delete(name);
    if (store.read(name) != null) return 'still there after delete';
    final afresh = await AndroidKeystore.open();
    return afresh.read(name) == null ? 'ok' : 'still kept after delete';
  } catch (e) {
    return 'failed: $e';
  }
}

/// A wallet saved in the app's folder opens again from its password in the
/// Keystore, and Remove wallet deletes the files and the password.
Future<String> _savedWallet() async {
  try {
    final folder = File(walletFile!).parent;
    // Filed by the file's name, not its path.
    const passwordName = 'Monero View Wallet: wallet';
    final manager = MoneroWalletManagerFactory().getWalletManager();
    final throwaway = manager.createWallet(
      path: '',
      password: '',
      networkType: Network.stagenet.id,
    );
    final address = throwaway.address();
    var wallet = ViewWallet.create(
      address: address,
      viewKey: throwaway.secretViewKey(),
      restoreHeight: 1234,
      save: true,
    );
    manager.closeWallet(throwaway, false);
    if (secretStore.read(passwordName) == null) return 'no password stored';
    // What connect() leaves, without connecting.
    await wallet.save({'mvw.node': '127.0.0.1:9'});
    await wallet.close();
    // As at the next launch: the password as the Keystore kept it.
    secretStore = await AndroidKeystore.open();
    final reopened = ViewWallet.openSaved();
    if (reopened == null) return 'did not open again';
    wallet = reopened;
    if (wallet.address != address || wallet.restoreHeight != 1234) {
      await wallet.forget();
      return 'opened a different wallet';
    }
    await wallet.forget();
    final left = folder.listSync().map((f) => f.uri.pathSegments.last);
    if (left.any((name) => name.startsWith('wallet'))) {
      return 'files left after remove';
    }
    if (secretStore.read(passwordName) != null) {
      return 'password left after remove';
    }
    if ((await AndroidKeystore.open()).read(passwordName) != null) {
      return 'password still kept after remove';
    }
    return ViewWallet.openSaved() == null && !ViewWallet.savedButUnreadable
        ? 'ok'
        : 'still there after remove';
  } catch (e) {
    return 'failed: $e';
  }
}
