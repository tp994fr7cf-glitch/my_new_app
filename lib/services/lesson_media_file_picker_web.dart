import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart';

import 'lesson_media_file_picker_error.dart';

const _overlayId = 'lesson-media-file-picker-overlay';
const _inputId = 'lesson-media-file-picker-input';
const _cancelButtonId = 'lesson-media-file-picker-cancel';
const _titleId = 'lesson-media-file-picker-title';
const _descriptionId = 'lesson-media-file-picker-description';
void Function()? _cancelActivePicker;

Future<PlatformFile?> pickLessonMediaFileForPlatform({
  required String mediaLabel,
  required List<String> allowedExtensions,
  required FileType pickerType,
  required int maxBytes,
}) {
  final body = document.body;
  if (body == null) {
    throw StateError('ファイル選択画面を表示できませんでした。');
  }

  _cancelActivePicker?.call();

  final completer = Completer<PlatformFile?>();
  var completed = false;
  var readingFile = false;
  late final void Function() cancelThisPicker;
  final previousFocus = document.activeElement as HTMLElement?;
  final backgroundInertStates = <(HTMLElement, bool)>[];

  final overlay = HTMLDivElement()
    ..id = _overlayId
    ..setAttribute('role', 'dialog')
    ..setAttribute('aria-modal', 'true')
    ..setAttribute('aria-labelledby', _titleId)
    ..setAttribute('aria-describedby', _descriptionId)
    ..style.cssText = '''
      position: fixed;
      inset: 0;
      z-index: 2147483647;
      display: flex;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
      padding: 24px;
      background: rgba(0, 0, 0, 0.54);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    ''';

  final card = HTMLDivElement()
    ..style.cssText = '''
      width: min(100%, 360px);
      box-sizing: border-box;
      padding: 24px;
      border-radius: 16px;
      background: #ffffff;
      color: #1d1b20;
      box-shadow: 0 8px 28px rgba(0, 0, 0, 0.28);
    ''';

  final title = HTMLHeadingElement.h2()
    ..id = _titleId
    ..textContent = '$mediaLabelファイルを選択'
    ..style.cssText = '''
      margin: 0 0 12px;
      font-size: 20px;
      line-height: 1.4;
    ''';

  final description = HTMLParagraphElement()
    ..id = _descriptionId
    ..textContent = '下のボタンを押して、端末内の$mediaLabelファイルを選んでください。'
    ..style.cssText = '''
      margin: 0 0 20px;
      font-size: 15px;
      line-height: 1.6;
    ''';

  final chooseButton = HTMLDivElement()
    ..textContent = 'ファイルを選ぶ'
    ..style.cssText = '''
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      min-height: 48px;
      box-sizing: border-box;
      overflow: hidden;
      border-radius: 24px;
      background: #6750a4;
      color: #ffffff;
      font-size: 15px;
      font-weight: 600;
    ''';

  final input = HTMLInputElement()
    ..id = _inputId
    ..type = 'file'
    ..accept = allowedExtensions.map((extension) => '.$extension').join(',')
    ..multiple = false
    ..setAttribute('aria-label', '$mediaLabelファイルを選ぶ')
    ..style.cssText = '''
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      margin: 0;
      opacity: 0;
      cursor: pointer;
    ''';

  final cancelButton = HTMLButtonElement()
    ..id = _cancelButtonId
    ..type = 'button'
    ..textContent = 'キャンセル'
    ..style.cssText = '''
      display: block;
      width: 100%;
      min-height: 44px;
      margin: 12px 0 0;
      border: 0;
      background: transparent;
      color: #6750a4;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
    ''';

  void restoreBackgroundInteraction() {
    for (final (element, wasInert) in backgroundInertStates) {
      element.inert = wasInert;
    }
  }

  void finish(PlatformFile? file) {
    if (completed) {
      return;
    }
    completed = true;
    if (identical(_cancelActivePicker, cancelThisPicker)) {
      _cancelActivePicker = null;
    }
    overlay.remove();
    restoreBackgroundInteraction();
    if (previousFocus != null && previousFocus.isConnected) {
      previousFocus.focus();
    }
    completer.complete(file);
  }

  void fail(Object error) {
    if (completed) {
      return;
    }
    completed = true;
    if (identical(_cancelActivePicker, cancelThisPicker)) {
      _cancelActivePicker = null;
    }
    overlay.remove();
    restoreBackgroundInteraction();
    if (previousFocus != null && previousFocus.isConnected) {
      previousFocus.focus();
    }
    completer.completeError(error);
  }

  cancelThisPicker = () => finish(null);
  _cancelActivePicker = cancelThisPicker;

  input.addEventListener(
    'change',
    ((Event _) {
      if (readingFile) {
        return;
      }
      final files = input.files;
      final file = files == null || files.length == 0 ? null : files.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      if (file.size > maxBytes) {
        fail(const LessonMediaFilePickerException('ファイルサイズは50MB以下にしてください。'));
        return;
      }

      readingFile = true;
      input.disabled = true;
      file.arrayBuffer().toDart.then(
        (buffer) {
          try {
            final Uint8List bytes = buffer.toDart.asUint8List();
            finish(
              PlatformFile(name: file.name, size: file.size, bytes: bytes),
            );
          } catch (error) {
            fail(StateError('選択したファイルを読み取れませんでした: $error'));
          }
        },
        onError: (Object error) {
          fail(StateError('選択したファイルを読み取れませんでした: $error'));
        },
      );
    }).toJS,
  );
  input.addEventListener('cancel', ((Event _) => finish(null)).toJS);
  input.addEventListener(
    'focus',
    ((Event _) {
      chooseButton.style.boxShadow = '0 0 0 3px rgba(103, 80, 164, 0.35)';
    }).toJS,
  );
  input.addEventListener(
    'blur',
    ((Event _) {
      chooseButton.style.boxShadow = 'none';
    }).toJS,
  );
  cancelButton.addEventListener(
    'click',
    ((Event event) {
      event.preventDefault();
      finish(null);
    }).toJS,
  );

  chooseButton.appendChild(input);
  card
    ..appendChild(title)
    ..appendChild(description)
    ..appendChild(chooseButton)
    ..appendChild(cancelButton);
  overlay.appendChild(card);
  for (var index = 0; index < body.children.length; index++) {
    final element = body.children.item(index) as HTMLElement;
    backgroundInertStates.add((element, element.inert));
    element.inert = true;
  }
  body.appendChild(overlay);
  input.focus();

  return completer.future;
}

void cancelLessonMediaFilePickerForPlatform() {
  _cancelActivePicker?.call();
}
