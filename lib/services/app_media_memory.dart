import 'package:flutter/painting.dart';

/// Drops decoded images that can remain after a lesson or live page closes.
///
/// PDF page bitmaps held by pdfrx are released when those widgets dispose.
/// This clears Flutter's process-wide [ImageCache], which logout and route
/// pops do not empty on their own.
void releaseAppMediaMemory() {
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();
}
