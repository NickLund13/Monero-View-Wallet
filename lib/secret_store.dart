/// The device's secure storage, where the saved wallet's password is kept.
library;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

abstract interface class SecretStore {
  /// The secret stored under [name], or null if there is none.
  String? read(String name);

  /// Stores [secret] under [name], replacing what was there. False if the
  /// device refuses.
  bool write(String name, String secret);

  /// Deletes the secret stored under [name], if there is one.
  void delete(String name);
}

/// The store the app uses: Credential Manager on Windows, and the Keychain
/// (keychain.dart), which main() picks, on iPhone. A variable so a test can
/// stand in for it where there is neither.
// ponytail: Android has no store yet. It needs the Keystore before its build
// can save the wallet.
SecretStore secretStore = const CredentialManager();

/// Windows Credential Manager, called directly so the app needs no plugin.
///
/// Windows encrypts a credential with the signed-in user's own key. Any
/// program running as that user can ask for it, though: unlike the iPhone
/// Keychain, it is not private to this app.
class CredentialManager implements SecretStore {
  const CredentialManager();

  @override
  String? read(String name) => using((arena) {
    final found = arena<Pointer<_Credential>>();
    if (_credRead(name.toNativeUtf16(allocator: arena), _generic, 0, found) ==
        0) {
      return null;
    }
    try {
      final credential = found.value.ref;
      return utf8.decode(credential.blob.asTypedList(credential.blobSize));
    } finally {
      _credFree(found.value.cast());
    }
  });

  @override
  bool write(String name, String secret) => using((arena) {
    final bytes = utf8.encode(secret);
    final blob = arena<Uint8>(bytes.length);
    final credential = arena<_Credential>();
    credential.ref
      ..type = _generic
      ..targetName = name.toNativeUtf16(allocator: arena)
      ..blobSize = bytes.length
      ..blob = blob
      ..persist = _thisComputerOnly;
    blob.asTypedList(bytes.length).setAll(0, bytes);
    try {
      return _credWrite(credential, 0) != 0;
    } finally {
      // Don't leave this copy of the secret in freed memory.
      blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
    }
  });

  @override
  void delete(String name) => using((arena) {
    _credDelete(name.toNativeUtf16(allocator: arena), _generic, 0);
  });
}

// CREDENTIALW from wincred.h.
final class _Credential extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  // FILETIME LastWritten
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int blobSize;
  external Pointer<Uint8> blob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

// CRED_TYPE_GENERIC
const _generic = 1;
// CRED_PERSIST_LOCAL_MACHINE: kept on this computer only. It does not roam to
// the user's other computers the way CRED_PERSIST_ENTERPRISE does.
const _thisComputerOnly = 2;

final _advapi = DynamicLibrary.open('advapi32.dll');
final _credWrite = _advapi
    .lookupFunction<
      Int32 Function(Pointer<_Credential>, Uint32),
      int Function(Pointer<_Credential>, int)
    >('CredWriteW');
final _credRead = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Pointer<_Credential>>,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer<Pointer<_Credential>>)
    >('CredReadW');
final _credDelete = _advapi
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32),
      int Function(Pointer<Utf16>, int, int)
    >('CredDeleteW');
final _credFree = _advapi
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CredFree',
    );
