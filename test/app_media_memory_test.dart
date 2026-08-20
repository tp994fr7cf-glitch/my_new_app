import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/app_media_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('releaseAppMediaMemory clears Flutter image cache', () {
    final cache = PaintingBinding.instance.imageCache;
    releaseAppMediaMemory();
    expect(cache.currentSize, 0);
    expect(cache.currentSizeBytes, 0);
  });
}
