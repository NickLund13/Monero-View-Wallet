// How the app holds a key images file it was handed, and deletes its copy.
// The files here are made up text in a temporary folder, not key images.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_view_wallet/pick_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mvw_test'));
  tearDown(() {
    receivedKeyImagesFile.value = null;
    dir.deleteSync(recursive: true);
  });

  /// A copy as the iPhone keeps it: alone in a folder of its own.
  KeyImagesFile copy(String name) {
    final folder = Directory('${dir.path}/KeyImages/$name')
      ..createSync(recursive: true);
    final file = File('${folder.path}/$name')..writeAsStringSync('not real');
    return KeyImagesFile(file.path, copy: true);
  }

  bool exists(KeyImagesFile file) => File(file.path).existsSync();

  test("deletes the app's own copy and its folder, never the user's file", () {
    final users = File('${dir.path}/key_images')..writeAsStringSync('not real');
    KeyImagesFile(users.path).discard();
    expect(users.existsSync(), isTrue);

    final kept = copy('exported');
    expect(kept.name, 'exported');
    kept.discard();
    expect(exists(kept), isFalse);
    expect(File(kept.path).parent.existsSync(), isFalse);
    expect(
      Directory('${dir.path}/KeyImages').existsSync(),
      isTrue,
      reason: 'only the folder that held the copy',
    );
    kept.discard(); // Twice does no harm.

    // A folder that holds anything else stays, with what it holds.
    final shared = File('${dir.path}/shared')..writeAsStringSync('not real');
    KeyImagesFile(shared.path, copy: true).discard();
    expect(shared.existsSync(), isFalse);
    expect(dir.existsSync(), isTrue);
  });

  test('a newer file replaces the one waiting, which is deleted', () {
    final first = copy('first');
    final second = copy('second');
    offerKeyImagesFile(first);
    offerKeyImagesFile(second);
    expect(exists(first), isFalse);
    expect(receivedKeyImagesFile.value, same(second));
    expect(takeKeyImagesFile(), same(second));
    expect(receivedKeyImagesFile.value, isNull);
    expect(exists(second), isTrue, reason: 'whoever took it deletes it');
  });

  test('takes the files iOS hands over, at start and when told', () async {
    const channel = MethodChannel('monero_view_wallet/key_images_file');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final started = copy('started');
    var waiting = [started.path];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'take') return null;
      final taken = waiting;
      waiting = [];
      return taken;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    // The file that started the app was waiting before the app listened.
    await receiveKeyImagesFiles();
    expect(receivedKeyImagesFile.value?.path, started.path);
    expect(receivedKeyImagesFile.value?.copy, isTrue);

    // Two at once while it runs: the newest one waits, the rest are deleted.
    final first = copy('first');
    final second = copy('second');
    waiting = [first.path, second.path];
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('received')),
      (_) {},
    );
    await pumpEventQueue();
    expect(receivedKeyImagesFile.value?.path, second.path);
    expect(exists(started), isFalse);
    expect(exists(first), isFalse);
    expect(exists(second), isTrue);
  });
}
