import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/utils/await_or_timeout.dart';

void main() {
  test('awaitOrTimeout returns after the timeout without cancelling work', () async {
    final work = Completer<void>();
    final startedAt = DateTime.now();

    await awaitOrTimeout(
      work.future,
      timeout: const Duration(milliseconds: 20),
      debugLabel: 'test-hang',
    );

    expect(DateTime.now().difference(startedAt).inMilliseconds, lessThan(500));
    expect(work.isCompleted, isFalse);
  });

  test('awaitOrTimeout returns immediately when the future is null', () async {
    await awaitOrTimeout(
      null,
      timeout: const Duration(seconds: 1),
      debugLabel: 'test-null',
    );
  });
}
