/// The iPhone's Keychain, where the saved wallet's password is kept, and the
/// setting that keeps the app's files out of backups. Both are Apple's own C
/// functions, called directly so the app needs no plugin.
library;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'secret_store.dart';

/// The Keychain's generic password items, filed under this app's service name
/// and the secret's name.
///
/// Only this app can read its items, only while the iPhone is unlocked, and
/// only on this iPhone: they are left out of iCloud Keychain and out of
/// backups restored to another phone.
class Keychain implements SecretStore {
  const Keychain();

  @override
  String? read(String name) => using((arena) {
    final found = arena<Pointer<Void>>();
    final query = _dictionary({
      ..._item(name, arena),
      _sec('kSecReturnData'): _true,
      _sec('kSecMatchLimit'): _sec('kSecMatchLimitOne'),
    }, arena);
    if (_secItemCopyMatching(query, found) != _ok) return null;
    final data = _owned(found.value, arena);
    return utf8.decode(
      _cfDataGetBytePtr(data).asTypedList(_cfDataGetLength(data)),
    );
  });

  @override
  bool write(String name, String secret) => using((arena) {
    delete(name);
    final bytes = utf8.encode(secret);
    final buffer = arena<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    final data = _owned(_cfDataCreate(nullptr, buffer, bytes.length), arena);
    // Don't leave this copy of the secret in freed memory.
    buffer.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
    final item = _dictionary({
      ..._item(name, arena),
      _sec('kSecAttrAccessible'): _sec(
        'kSecAttrAccessibleWhenUnlockedThisDeviceOnly',
      ),
      _sec('kSecValueData'): data,
    }, arena);
    return _secItemAdd(item, nullptr) == _ok;
  });

  @override
  void delete(String name) => using((arena) {
    _secItemDelete(_dictionary(_item(name, arena), arena));
  });

  static Map<Pointer<Void>, Pointer<Void>> _item(String name, Arena arena) => {
    _sec('kSecClass'): _sec('kSecClassGenericPassword'),
    _sec('kSecAttrService'): _string('Monero View Wallet', arena),
    _sec('kSecAttrAccount'): _string(name, arena),
  };
}

/// Keeps the folder at [path], and everything in it, out of iCloud and
/// computer backups of the iPhone. False if iOS refuses.
bool excludeFromBackup(String path) => using((arena) {
  final bytes = utf8.encode(path);
  final buffer = arena<Uint8>(bytes.length);
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  final url = _owned(
    _cfUrlCreateFromFileSystemRepresentation(nullptr, buffer, bytes.length, 1),
    arena,
  );
  if (url == nullptr) return false;
  return _cfUrlSetResourcePropertyForKey(
        url,
        _cf.lookup<Pointer<Void>>('kCFURLIsExcludedFromBackupKey').value,
        _true,
        nullptr,
      ) !=
      0;
});

/// Releases [object] with the [arena], unless it is null.
Pointer<Void> _owned(Pointer<Void> object, Arena arena) =>
    object == nullptr ? object : arena.using(object, _cfRelease);

Pointer<Void> _string(String text, Arena arena) => _owned(
  _cfStringCreateWithCString(
    nullptr,
    text.toNativeUtf8(allocator: arena),
    _utf8,
  ),
  arena,
);

/// A CFDictionary, which keeps its own reference to each key and value.
Pointer<Void> _dictionary(
  Map<Pointer<Void>, Pointer<Void>> entries,
  Arena arena,
) {
  final keys = arena<Pointer<Void>>(entries.length);
  final values = arena<Pointer<Void>>(entries.length);
  var i = 0;
  entries.forEach((key, value) {
    keys[i] = key;
    values[i++] = value;
  });
  return _owned(
    _cfDictionaryCreate(
      nullptr,
      keys,
      values,
      entries.length,
      _cf.lookup('kCFTypeDictionaryKeyCallBacks'),
      _cf.lookup('kCFTypeDictionaryValueCallBacks'),
    ),
    arena,
  );
}

/// One of Security's constants, such as kSecClass.
Pointer<Void> _sec(String name) => _security.lookup<Pointer<Void>>(name).value;

// errSecSuccess
const _ok = 0;
// kCFStringEncodingUTF8
const _utf8 = 0x08000100;

final _cf = DynamicLibrary.open(
  '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
);
final _security = DynamicLibrary.open(
  '/System/Library/Frameworks/Security.framework/Security',
);
final _true = _cf.lookup<Pointer<Void>>('kCFBooleanTrue').value;

final _cfRelease = _cf
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CFRelease',
    );
final _cfStringCreateWithCString = _cf
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)
    >('CFStringCreateWithCString');
final _cfDataCreate = _cf
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Long),
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)
    >('CFDataCreate');
final _cfDataGetLength = _cf
    .lookupFunction<Long Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CFDataGetLength',
    );
final _cfDataGetBytePtr = _cf
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)
    >('CFDataGetBytePtr');
final _cfDictionaryCreate = _cf
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Long,
        Pointer<Void>,
        Pointer<Void>,
      ),
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        int,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('CFDictionaryCreate');
final _cfUrlCreateFromFileSystemRepresentation = _cf
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Long, Uint8),
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int)
    >('CFURLCreateFromFileSystemRepresentation');
final _cfUrlSetResourcePropertyForKey = _cf
    .lookupFunction<
      Uint8 Function(
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Pointer<Void>>,
      )
    >('CFURLSetResourcePropertyForKey');
final _secItemAdd = _security
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    >('SecItemAdd');
final _secItemCopyMatching = _security
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    >('SecItemCopyMatching');
final _secItemDelete = _security
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'SecItemDelete',
    );
