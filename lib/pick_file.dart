/// Where the key images file comes from: the Windows "Open" dialog; on an
/// iPhone the Files picker and files opened with the app from Files, the share
/// sheet or AirDrop (ios/Runner/KeyImagesFile.swift is the other end); on
/// Android the system's file picker and files opened with the app or shared to
/// it (KeyImagesFile.kt).
// ponytail: on Windows the dialog is its own window rather than a child of the
// app's.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A key images file to import.
class KeyImagesFile {
  const KeyImagesFile(this.path, {this.copy = false});

  final String path;

  /// True for the app's own copy, made on a phone when the file was chosen or
  /// opened with the app, and which [discard] deletes. False for the file the
  /// Windows dialog chose, which stays where it is.
  final bool copy;

  String get name => path.split(RegExp(r'[/\\]')).last;

  /// In bytes, 0 if the file can't be read.
  int get size {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  /// Deletes the app's copy, and the folder the phone kept it in if that is
  /// now empty. The wallet keeps what it imported; the file isn't needed again.
  void discard() {
    if (!copy) return;
    final file = File(path);
    for (final entry in [file, file.parent]) {
      try {
        // Not recursive: a folder that still holds anything stays.
        entry.deleteSync();
      } on FileSystemException {
        // Already gone, or not empty.
      }
    }
  }
}

/// Asks for the key images file; null if the dialog or picker was cancelled.
/// A variable so a test can stand in for the dialog.
Future<KeyImagesFile?> Function() pickKeyImagesFile =
    Platform.isIOS || Platform.isAndroid
    ? _pickOnPhone
    : () async {
        final path = await Isolate.run(_openDialog);
        return path == null ? null : KeyImagesFile(path);
      };

/// The newest file opened with the app from elsewhere, until the Import key
/// images screen takes it (or, without a wallet, setup turns it away).
final receivedKeyImagesFile = ValueNotifier<KeyImagesFile?>(null);

/// Makes [file] the one waiting in [receivedKeyImagesFile], deleting any it
/// replaces.
void offerKeyImagesFile(KeyImagesFile file) {
  receivedKeyImagesFile.value?.discard();
  receivedKeyImagesFile.value = file;
}

/// Takes the file waiting in [receivedKeyImagesFile], if any, so whoever
/// deletes it is the only one holding it.
KeyImagesFile? takeKeyImagesFile() {
  final file = receivedKeyImagesFile.value;
  receivedKeyImagesFile.value = null;
  return file;
}

const _phone = MethodChannel('monero_view_wallet/key_images_file');

Future<KeyImagesFile?> _pickOnPhone() async {
  try {
    final path = await _phone.invokeMethod<String>('pick');
    return path == null ? null : KeyImagesFile(path, copy: true);
  } on PlatformException {
    // The picker couldn't be shown just now: as if cancelled.
    return null;
  }
}

/// On a phone, starts taking the files opened with the app, including one
/// that started it.
Future<void> receiveKeyImagesFiles() async {
  _phone.setMethodCallHandler((call) async {
    if (call.method == 'received') await _take();
  });
  await _take();
}

Future<void> _take() async {
  final paths = await _phone.invokeListMethod<String>('take') ?? const [];
  for (final path in paths) {
    offerKeyImagesFile(KeyImagesFile(path, copy: true));
  }
}

// OPENFILENAMEW from commdlg.h.
final class _OpenFileName extends Struct {
  @Uint32()
  external int lStructSize;
  external Pointer<Void> hwndOwner;
  external Pointer<Void> hInstance;
  external Pointer<Utf16> lpstrFilter;
  external Pointer<Utf16> lpstrCustomFilter;
  @Uint32()
  external int nMaxCustFilter;
  @Uint32()
  external int nFilterIndex;
  external Pointer<Utf16> lpstrFile;
  @Uint32()
  external int nMaxFile;
  external Pointer<Utf16> lpstrFileTitle;
  @Uint32()
  external int nMaxFileTitle;
  external Pointer<Utf16> lpstrInitialDir;
  external Pointer<Utf16> lpstrTitle;
  @Uint32()
  external int flags;
  @Uint16()
  external int nFileOffset;
  @Uint16()
  external int nFileExtension;
  external Pointer<Utf16> lpstrDefExt;
  @IntPtr()
  external int lCustData;
  external Pointer<Void> lpfnHook;
  external Pointer<Utf16> lpTemplateName;
  external Pointer<Void> pvReserved;
  @Uint32()
  external int dwReserved;
  @Uint32()
  external int flagsEx;
}

const _maxPath = 32768;

// OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY
const _dialogFlags = 0x00080000 | 0x00001000 | 0x00000800 | 0x00000004;
// Leave the app's working folder alone, and keep the file out of Windows'
// "Recent files" lists.
const _noChangeDir = 0x00000008;
const _dontAddToRecent = 0x02000000;

// Runs on its own isolate: the dialog blocks its thread until it is closed.
String? _openDialog() {
  final getOpenFileName = DynamicLibrary.open('comdlg32.dll')
      .lookupFunction<
        Int32 Function(Pointer<_OpenFileName>),
        int Function(Pointer<_OpenFileName>)
      >('GetOpenFileNameW');
  return using((arena) {
    final file = arena<Uint16>(_maxPath).cast<Utf16>();
    final dialog = arena<_OpenFileName>();
    dialog.ref
      ..lStructSize = sizeOf<_OpenFileName>()
      ..lpstrFile = file
      ..nMaxFile = _maxPath
      ..lpstrTitle = 'Choose the key images file'.toNativeUtf16(
        allocator: arena,
      )
      ..flags = _dialogFlags | _noChangeDir | _dontAddToRecent;
    return getOpenFileName(dialog) == 0 ? null : file.toDartString();
  });
}
