// Not the app: the iOS build workflow (.github/workflows/ios-build.yml) runs
// this on the iOS simulator to check that the wallet library is embedded and
// works on iOS, that the wallet is saved in the app's folder with its password
// in the Keychain and opens again, that the app's native code for key images
// files and the lock's checks answer, that the Tor inside the app runs and
// answers on its control port, that the camera's native code answers, and
// that the app draws its first screen.
//
// The library is called with obviously fake input (no real address or key).
// The saved wallet is a random throwaway made here, as in the app's tests,
// and deleted again with its password. Only "ok" or the error goes to
// ios_smoke.txt in the app's temporary folder, where the workflow reads it.
// Nothing goes to the network: the saved wallet's node is 127.0.0.1 port 9,
// where nothing listens, and Tor is left off the network, as the app starts
// it.

import 'dart:io';

import 'package:flutter/widgets.dart';
// ignore_for_file: implementation_imports
import 'package:monero/src/monero.dart';
import 'package:monero_view_wallet/keychain.dart';
import 'package:monero_view_wallet/lock.dart';
import 'package:monero_view_wallet/main.dart';
import 'package:monero_view_wallet/pick_file.dart';
import 'package:monero_view_wallet/scan_screen.dart';
import 'package:monero_view_wallet/secret_store.dart';
import 'package:monero_view_wallet/tor.dart';
import 'package:monero_view_wallet/wallet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final out = File('${Directory.systemTemp.path}/ios_smoke.txt');
  out.writeAsStringSync('wallet library: ${_walletLibrary()}\n');
  keepOnDevice();
  out.writeAsStringSync('keychain: ${_keychain()}\n', mode: FileMode.append);
  out.writeAsStringSync(
    'saved wallet: ${await _savedWallet()}\n',
    mode: FileMode.append,
  );
  out.writeAsStringSync(
    'key images file: ${await _keyImagesFile()}\n',
    mode: FileMode.append,
  );
  out.writeAsStringSync('lock: ${await _lock()}\n', mode: FileMode.append);
  out.writeAsStringSync('tor: ${await _tor()}\n', mode: FileMode.append);
  out.writeAsStringSync('camera: ${await _camera()}\n', mode: FileMode.append);
  runApp(const MainApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    out.writeAsStringSync('first frame: ok\n', mode: FileMode.append);
    out.writeAsStringSync(
      'face id: ${await _faceId()}\n',
      mode: FileMode.append,
    );
  });
}

/// The lock's checks answer through ios/Runner/AppDelegate.swift. No face is
/// enrolled yet, so the lock can't offer Face ID, and the Face ID check says
/// so at once, without showing anything. The simulator may count as having a
/// passcode (it does in Xcode 26); only without one is the passcode check
/// asked, which then also says why at once instead of showing the passcode
/// sheet.
Future<String> _lock() async {
  try {
    const check = IosOwnerCheck();
    const wait = Duration(seconds: 20);
    final kind = await check.kind().timeout(wait);
    if (kind != Unlock.passcode && kind != Unlock.none) {
      return 'unexpected: can lock with ${kind.name}';
    }
    final faceId = await check
        .ask(reason: 'Smoke test', passcode: false)
        .timeout(wait);
    if (faceId == CheckResult.ok || faceId == CheckResult.cancelled) {
      return 'unexpected: Face ID ${faceId.name}';
    }
    if (kind == Unlock.passcode) return 'ok';
    final passcode = await check
        .ask(reason: 'Smoke test', passcode: true)
        .timeout(wait);
    return passcode == CheckResult.noPasscode
        ? 'ok'
        : 'unexpected: passcode ${passcode.name}';
  } catch (e) {
    return 'failed: $e';
  }
}

/// Once the workflow has enrolled a face in the simulator, the lock offers
/// Face ID.
Future<String> _faceId() async {
  try {
    var kind = Unlock.none;
    for (var i = 0; i < 60 && kind != Unlock.faceId; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      kind = await const IosOwnerCheck().kind();
    }
    return kind == Unlock.faceId ? 'ok' : 'still ${kind.name}';
  } catch (e) {
    return 'failed: $e';
  }
}

/// The Tor inside the app (ios/Runner/InAppTor.swift) starts with the app's
/// own command line, which keeps it off the network, takes the cookie it
/// wrote and says it is the tor that tool/fetch_tor.sh pins.
Future<String> _tor() async {
  try {
    final folder = torFolder;
    if (!torInApp || folder == null) return 'not in use';
    final state = await runTorInApp(inAppTorArguments(folder))
        .timeout(const Duration(seconds: 20));
    if (state != 'started') return 'unexpected: $state';
    final control = await TorControl.open(
      torControlAddress,
      File('$folder/control_auth_cookie'),
    );
    final version = await control.command('GETINFO version');
    control.close();
    return version.first.startsWith('250-version=0.4.9.13')
        ? 'ok'
        : 'unexpected: ${version.first}';
  } catch (e) {
    return 'failed: $e';
  }
}

/// The camera's native code (ios/Runner/QrCamera.swift) answers, without
/// asking for the camera, which nobody on the simulator could allow: the app
/// was just installed, so the question hasn't been asked yet. Stopping a
/// camera view that doesn't exist does nothing. Key images by QR keeps the
/// screen on, and lets it sleep again.
Future<String> _camera() async {
  try {
    final status = await IosQrCamera.channel.invokeMethod<String>('status');
    await IosQrCamera.channel.invokeMethod<void>('stop', -1);
    await IosQrCamera.channel.invokeMethod<void>('keepScreenOn', true);
    await IosQrCamera.channel.invokeMethod<void>('keepScreenOn', false);
    return status == 'notDetermined' ? 'ok' : 'unexpected: $status';
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

/// The Keychain stores, replaces and deletes an item.
String _keychain() {
  try {
    if (secretStore is! Keychain) return 'not in use';
    const name = 'Monero View Wallet: smoke test';
    secretStore.delete(name);
    if (secretStore.read(name) != null) return 'delete failed';
    for (final secret in ['not a real secret', 'replaced']) {
      if (!secretStore.write(name, secret)) return 'write refused';
      if (secretStore.read(name) != secret) return 'read back wrong';
    }
    secretStore.delete(name);
    return secretStore.read(name) == null ? 'ok' : 'still there after delete';
  } catch (e) {
    return 'failed: $e';
  }
}

/// ios/Runner/KeyImagesFile.swift answers on its channel, with no file waiting:
/// the app wasn't opened with one. The workflow checks that it deleted the
/// leftovers put where iOS leaves files for the app.
Future<String> _keyImagesFile() async {
  try {
    await receiveKeyImagesFiles();
    return receivedKeyImagesFile.value == null ? 'ok' : 'a file is waiting';
  } catch (e) {
    return 'failed: $e';
  }
}

/// A wallet saved in the app's folder opens again from its password in the
/// Keychain, and Remove wallet deletes the files and the password.
Future<String> _savedWallet() async {
  try {
    final folder = File(walletFile!).parent;
    if (!excludeFromBackup(folder.path)) return 'not kept out of backups';
    // Filed by the file's name, not its path, which changes with app updates.
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
    return ViewWallet.openSaved() == null && !ViewWallet.savedButUnreadable
        ? 'ok'
        : 'still there after remove';
  } catch (e) {
    return 'failed: $e';
  }
}
