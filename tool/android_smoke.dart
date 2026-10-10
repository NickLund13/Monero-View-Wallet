// Not the app: the Android build workflow (.github/workflows/android-build.yml)
// runs this on the Android emulator, as a release build, to check that the
// wallet library is in the app and works on Android, that the wallet is saved
// in the app's own folder with its password in the Keystore, that the
// password is still there when the Keystore is read afresh, as at the next
// launch, that the app's native code for key images files and the lock
// answers, and that the app draws its first screen. Once tool/android_smoke.sh
// has set a screen lock, the lock asks for it with Android's own prompt, where
// the script enters it. The script then starts the app a second time, which
// checks that the copy of a key images file the first one left behind was
// deleted at launch.
//
// The library is called with obviously fake input (no real address or key).
// The saved wallet is a random throwaway made here, as in the app's tests, and
// deleted again with its password. The key images file left behind is made up
// text. Only "ok" or the error is printed, each line starting
// "android_smoke: ", and read by tool/android_smoke.sh from the emulator's
// log, together with the names of the files the app keeps. Nothing goes to the
// network: the saved wallet's node is 127.0.0.1 port 9, where nothing listens.

import 'dart:io';

import 'package:flutter/widgets.dart';
// ignore_for_file: implementation_imports, avoid_print
import 'package:monero/src/monero.dart';
import 'package:monero_view_wallet/android_keystore.dart';
import 'package:monero_view_wallet/lock.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/pick_file.dart';
import 'package:monero_view_wallet/secret_store.dart';
import 'package:monero_view_wallet/tor.dart';
import 'package:monero_view_wallet/wallet.dart';

void report(String line) => print('android_smoke: $line');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final home = Platform.environment['HOME'];
  // The second start (see _leaveCopy).
  final started = File('$home/android_smoke_started');
  if (home != null && started.existsSync()) {
    report(
      'copy left behind: '
      '${Directory('$home/KeyImages').existsSync() ? 'still there' : 'ok'}',
    );
    return;
  }
  report('wallet library: ${_walletLibrary()}');
  final folder = await keepOnDevice();
  report('folder: ${_folder(folder)}');
  report('keystore: ${await _keystore()}');
  report('saved wallet: ${await _savedWallet()}');
  report('no tor: ${hasTor ? 'unexpected: this build has Tor' : 'ok'}');
  report('key images file: ${await _keyImagesFile()}');
  report('lock: ${await _lock()}');
  // Names only, to show where the app and wallet2 keep their files.
  if (home != null) {
    for (final entry in Directory(home).listSync(recursive: true)) {
      report('file: ${entry.path.substring(home.length)}');
    }
    _leaveCopy(home);
    started.createSync();
  }
  runApp(const MainApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    report('first frame: ok');
    report('screen lock: ${await _screenLock()}');
  });
}

/// KeyImagesFile.kt answers on its channel, with no file waiting: the app
/// wasn't opened with one.
Future<String> _keyImagesFile() async {
  try {
    await receiveKeyImagesFiles();
    return receivedKeyImagesFile.value == null ? 'ok' : 'a file is waiting';
  } catch (e) {
    return 'failed: $e';
  }
}

/// A copy of a key images file, as if the app had stopped before it was
/// imported. The next start deletes it before the Dart code runs
/// (KeyImagesFile.kt), and reports whether it did.
void _leaveCopy(String home) {
  File('$home/KeyImages/left-behind/key images')
    ..createSync(recursive: true)
    ..writeAsStringSync('not real');
}

const _wait = Duration(seconds: 20);

/// The lock's checks answer through AppLock.kt, and so does taking its cover
/// off the app (with no cover up, nothing to do). The emulator has no screen
/// lock yet, so the app can't lock, and both checks say so at once, without
/// showing anything.
Future<String> _lock() async {
  try {
    const check = PhoneOwnerCheck();
    await AppLock().uncover().timeout(_wait);
    final kind = await check.kind().timeout(_wait);
    if (kind != Unlock.noScreenLock) return 'unexpected: ${kind.name}';
    for (final passcode in [false, true]) {
      final answer = await check
          .ask(reason: 'Smoke test', passcode: passcode)
          .timeout(_wait);
      if (answer != CheckResult.noPasscode) {
        return 'unexpected: ${passcode ? 'screen lock' : 'fingerprint'} '
            '${answer.name}';
      }
    }
    return 'ok';
  } catch (e) {
    return 'failed: $e';
  }
}

/// Once the script has set a PIN as the screen lock, the lock offers it. The
/// emulator has no fingerprint set up, so that check says so at once. The
/// screen lock check shows Android's own prompt, which the script answers with
/// the PIN.
Future<String> _screenLock() async {
  try {
    const check = PhoneOwnerCheck();
    var kind = Unlock.noScreenLock;
    for (var i = 0; i < 120 && kind != Unlock.screenLock; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      kind = await check.kind().timeout(_wait);
    }
    if (kind != Unlock.screenLock) return 'still ${kind.name}';
    final fingerprint = await check
        .ask(reason: 'Smoke test', passcode: false)
        .timeout(_wait);
    if (fingerprint != CheckResult.unavailable) {
      return 'unexpected: fingerprint ${fingerprint.name}';
    }
    report('screen lock: asking');
    final answer = await check
        .ask(reason: 'Smoke test', passcode: true)
        .timeout(const Duration(minutes: 2));
    return answer == CheckResult.ok ? 'ok' : 'unexpected: ${answer.name}';
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
