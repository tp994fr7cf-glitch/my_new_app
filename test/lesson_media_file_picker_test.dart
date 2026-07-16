import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_media_file_picker.dart';

import 'helpers/lesson_media_picker_dom_probe_stub.dart'
    if (dart.library.js_interop) 'helpers/lesson_media_picker_dom_probe_web.dart'
    as dom_probe;

void main() {
  test('Webのファイル入力を画面に接続した状態で表示する', () async {
    if (!dom_probe.isWeb) {
      return;
    }
    addTearDown(dom_probe.cancelPicker);

    final pickFuture = pickLessonMediaFileForPlatform(
      mediaLabel: '音声',
      allowedExtensions: const ['mp3', 'm4a'],
      pickerType: FileType.audio,
      maxBytes: 50 * 1024 * 1024,
    );

    expect(dom_probe.overlayExists, isTrue);
    expect(dom_probe.fileInputIsAttached, isTrue);
    expect(dom_probe.fileInputIsVisibleToPointer, isTrue);
    expect(dom_probe.fileInputReceivesCenterHit, isTrue);
    expect(dom_probe.backgroundIsInert, isTrue);

    dom_probe.cancelPicker();

    expect(await pickFuture, isNull);
    expect(dom_probe.overlayExists, isFalse);
    expect(dom_probe.backgroundIsInert, isFalse);
  });

  test('Webで次のファイル選択を始めたら前の選択を安全に終了する', () async {
    if (!dom_probe.isWeb) {
      return;
    }
    addTearDown(dom_probe.cancelPicker);

    final firstPick = pickLessonMediaFileForPlatform(
      mediaLabel: '音声',
      allowedExtensions: const ['mp3'],
      pickerType: FileType.audio,
      maxBytes: 50 * 1024 * 1024,
    );
    final secondPick = pickLessonMediaFileForPlatform(
      mediaLabel: '動画',
      allowedExtensions: const ['mp4'],
      pickerType: FileType.video,
      maxBytes: 50 * 1024 * 1024,
    );

    expect(await firstPick, isNull);
    expect(dom_probe.overlayExists, isTrue);
    expect(dom_probe.fileInputIsAttached, isTrue);

    dom_probe.cancelPicker();

    expect(await secondPick, isNull);
    expect(dom_probe.overlayExists, isFalse);
  });
}
