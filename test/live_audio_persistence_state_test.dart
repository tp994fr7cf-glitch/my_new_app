import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_probe_message.dart';
import 'package:my_new_app/services/live_audio_snapshot_tracker.dart';
import 'package:my_new_app/services/live_audio_timeline_outbox.dart';

void main() {
  group('LiveAudioTimelineOutbox', () {
    const createA = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardCreate,
      boardId: 'board-a',
      boardOrder: 1,
      boardTitle: 'ボード2',
      timestampSec: 1,
    );
    const switchA = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardSwitch,
      boardId: 'board-a',
      timestampSec: 1,
    );
    const createB = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardCreate,
      boardId: 'board-b',
      boardOrder: 2,
      boardTitle: 'ボード3',
      timestampSec: 2,
    );

    test('retries the exact failed batch before newer messages', () async {
      final outbox = LiveAudioTimelineOutbox()
        ..add(createA)
        ..add(switchA);
      var attempts = 0;

      await expectLater(
        outbox.flushNext(({required firstSequence, required messages}) async {
          attempts++;
          expect(firstSequence, 0);
          expect(messages, [createA, switchA]);
          throw TimeoutException('response lost');
        }),
        throwsA(isA<TimeoutException>()),
      );

      outbox.add(createB);
      await outbox.flushNext(({
        required firstSequence,
        required messages,
      }) async {
        attempts++;
        expect(firstSequence, 0);
        expect(messages, [createA, switchA]);
        return 2;
      });
      await outbox.flushNext(({
        required firstSequence,
        required messages,
      }) async {
        attempts++;
        expect(firstSequence, 2);
        expect(messages, [createB]);
        return 3;
      });

      expect(attempts, 3);
      expect(outbox.hasMessages, isFalse);
      expect(outbox.nextSequence, 3);
    });

    test('serializes overlapping flush requests', () async {
      final outbox = LiveAudioTimelineOutbox()..add(createA);
      final completion = Completer<int>();
      var saves = 0;

      final first = outbox.flushNext(({
        required firstSequence,
        required messages,
      }) {
        saves++;
        return completion.future;
      });
      final second = outbox.flushNext(({
        required firstSequence,
        required messages,
      }) async {
        saves++;
        return 1;
      });

      expect(saves, 1);
      completion.complete(1);
      await Future.wait([first, second]);
      expect(saves, 1);
      expect(outbox.hasMessages, isFalse);
    });

    test('does not replace its sequence while messages are pending', () {
      final outbox = LiveAudioTimelineOutbox();
      outbox.observeServerSequence(4);
      expect(outbox.nextSequence, 4);

      outbox.add(createA);
      outbox.observeServerSequence(8);
      expect(outbox.nextSequence, 4);
    });
  });

  group('LiveAudioSnapshotTracker', () {
    test(
      'applies the initial snapshot once and then requires a newer revision',
      () {
        final tracker = LiveAudioSnapshotTracker();

        expect(
          tracker.shouldApplyServerSnapshot(
            revision: 0,
            preserveUnsavedLocalChanges: false,
          ),
          isTrue,
        );

        tracker.markServerSnapshotApplied(0);

        expect(
          tracker.shouldApplyServerSnapshot(
            revision: 0,
            preserveUnsavedLocalChanges: false,
          ),
          isFalse,
        );
        expect(
          tracker.shouldApplyServerSnapshot(
            revision: 1,
            preserveUnsavedLocalChanges: false,
          ),
          isTrue,
        );

        tracker.markServerSnapshotApplied(1);

        expect(
          tracker.shouldApplyServerSnapshot(
            revision: 1,
            preserveUnsavedLocalChanges: false,
          ),
          isFalse,
        );
      },
    );

    test('keeps a locally changed board set dirty until it is saved', () {
      final tracker = LiveAudioSnapshotTracker();

      tracker.markChanged();
      tracker.observeServerRevision(1);

      expect(tracker.hasUnsavedChanges, isTrue);
      expect(tracker.serverRevision, 1);
      expect(
        tracker.shouldApplyServerSnapshot(
          revision: 1,
          preserveUnsavedLocalChanges: true,
        ),
        isFalse,
      );
    });

    test('does not lose a change made while a save is running', () {
      final tracker = LiveAudioSnapshotTracker()..markChanged();
      final savingGeneration = tracker.changeGeneration;

      tracker.markChanged();
      tracker.markSaved(generation: savingGeneration, revision: 1);

      expect(tracker.hasUnsavedChanges, isTrue);
      tracker.markSaved(generation: tracker.changeGeneration, revision: 2);
      expect(tracker.hasUnsavedChanges, isFalse);
      expect(tracker.serverRevision, 2);
    });

    test('rejects an older server snapshot after a newer save', () {
      final tracker = LiveAudioSnapshotTracker()..markChanged();
      tracker.markSaved(generation: tracker.changeGeneration, revision: 3);

      expect(
        tracker.shouldApplyServerSnapshot(
          revision: 2,
          preserveUnsavedLocalChanges: false,
        ),
        isFalse,
      );
      expect(
        tracker.shouldApplyServerSnapshot(
          revision: 3,
          preserveUnsavedLocalChanges: true,
        ),
        isTrue,
      );
    });
  });
}
