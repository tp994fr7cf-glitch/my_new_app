import 'package:web/web.dart';

const bool isWeb = true;

bool get overlayExists =>
    document.getElementById('lesson-media-file-picker-overlay') != null;

bool get fileInputIsAttached {
  final input =
      document.getElementById('lesson-media-file-picker-input')
          as HTMLInputElement?;
  return input != null && input.isConnected;
}

bool get fileInputIsVisibleToPointer {
  final input =
      document.getElementById('lesson-media-file-picker-input')
          as HTMLInputElement?;
  return input != null &&
      input.style.display != 'none' &&
      input.style.pointerEvents != 'none';
}

bool get fileInputReceivesCenterHit {
  final input =
      document.getElementById('lesson-media-file-picker-input')
          as HTMLInputElement?;
  if (input == null) {
    return false;
  }
  final rect = input.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) {
    return false;
  }
  final hit = document.elementFromPoint(
    rect.left + rect.width / 2,
    rect.top + rect.height / 2,
  );
  return hit == input;
}

void cancelPicker() {
  final button =
      document.getElementById('lesson-media-file-picker-cancel')
          as HTMLButtonElement?;
  button?.click();
}
