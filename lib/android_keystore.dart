/// Android's secure storage, where the saved wallet's password is kept.
/// android/app/src/main/kotlin/.../KeystoreSecrets.kt is the other end.
library;

import 'package:flutter/services.dart';

import 'secret_store.dart';

/// The secrets, encrypted with a key that the Android Keystore makes and
/// keeps: it can't be read out of the phone, backed up or moved to another
/// phone. The encrypted file is in the app's own folder, which Android never
/// backs up.
///
/// Android answers only asynchronously, while [SecretStore] answers at once,
/// as the iPhone's Keychain and Windows' Credential Manager do. So [open]
/// reads the secrets once at launch, before the wallet is opened, and [read]
/// answers from those. [write] and [delete] change them at once and pass the
/// change on, in order, to be kept. [write] refuses only when the Keystore
/// couldn't make its key at launch; should keeping a secret still fail after
/// that, the wallet it belongs to can't be opened at the next launch, and
/// setup says so.
class AndroidKeystore implements SecretStore {
  AndroidKeystore._(this._available, this._secrets);

  static const channel = MethodChannel('monero_view_wallet/keystore');

  /// The secrets kept so far. Call at launch, before [read].
  static Future<AndroidKeystore> open() async {
    try {
      final loaded = await channel.invokeMapMethod<String, Object?>('load');
      final secrets = loaded?['secrets'];
      return AndroidKeystore._(loaded?['available'] == true, {
        if (secrets is Map)
          for (final MapEntry(:key, :value) in secrets.entries)
            if (key is String && value is String) key: value,
      });
    } on PlatformException {
      return AndroidKeystore._(false, {});
    }
  }

  final bool _available;
  final Map<String, String> _secrets;

  @override
  String? read(String name) => _secrets[name];

  @override
  bool write(String name, String secret) {
    if (!_available) return false;
    _secrets[name] = secret;
    _keep('write', {'name': name, 'secret': secret});
    return true;
  }

  @override
  void delete(String name) {
    _secrets.remove(name);
    _keep('delete', {'name': name});
  }

  /// Passes a change on to the Keystore's side, which works through them one
  /// at a time in the order they were made.
  void _keep(String method, Map<String, String> arguments) {
    channel.invokeMethod<bool>(method, arguments).ignore();
  }
}
