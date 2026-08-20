import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long a lesson/live screen may wait for cleanup before going back.
const Duration kRouteExitCleanupTimeout = Duration(seconds: 4);

/// How long pause, dispose, or an in-flight prepare may block cleanup.
const Duration kNativeMediaOpTimeout = Duration(seconds: 2);

/// Waits for [future] up to [timeout], then continues.
///
/// The original future is not cancelled. Cleanup callers use this so a
/// stuck native player cannot block going back.
Future<void> awaitOrTimeout(
  Future<void>? future, {
  required Duration timeout,
  required String debugLabel,
  bool ignoreErrors = true,
}) async {
  if (future == null) {
    return;
  }
  try {
    await future.timeout(timeout);
  } on TimeoutException {
    debugPrint('$debugLabel timed out after ${timeout.inMilliseconds}ms');
  } catch (error, stackTrace) {
    debugPrint('$debugLabel failed: $error\n$stackTrace');
    if (!ignoreErrors) {
      rethrow;
    }
  }
}
