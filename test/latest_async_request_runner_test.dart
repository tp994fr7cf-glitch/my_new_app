import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/latest_async_request_runner.dart';

void main() {
  test(
    'runs one request at a time and keeps only the latest pending one',
    () async {
      final runner = LatestAsyncRequestRunner<int>();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final completed = <int>[];
      var activeOperations = 0;
      var maximumActiveOperations = 0;

      Future<void> operation(int request) async {
        activeOperations += 1;
        maximumActiveOperations = maximumActiveOperations < activeOperations
            ? activeOperations
            : maximumActiveOperations;
        if (request == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        completed.add(request);
        activeOperations -= 1;
      }

      final first = runner.run(1, operation);
      await firstStarted.future;
      final second = runner.run(2, operation);
      final third = runner.run(3, operation);
      releaseFirst.complete();

      await Future.wait([first, second, third]);

      expect(completed, [1, 3]);
      expect(maximumActiveOperations, 1);
      expect(runner.isRunning, isFalse);
    },
  );

  test('can run again after a previous operation fails', () async {
    final runner = LatestAsyncRequestRunner<int>();
    final error = StateError('failed');

    await expectLater(
      runner.run(1, (_) => Future<void>.error(error)),
      throwsA(same(error)),
    );
    await runner.run(2, (_) async {});

    expect(runner.isRunning, isFalse);
  });
}
