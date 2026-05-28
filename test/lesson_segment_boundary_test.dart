import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_segment_boundary.dart';

void main() {
  group('decideSegmentBoundary', () {
    const resumeWindow = Duration(hours: 24);
    final now = DateTime(2026, 5, 28, 8);

    test('resumes the same in-progress segment within the resume window', () {
      final decision = decideSegmentBoundary(
        previousTask: LearningTaskSnapshot(
          sessionId: 'session-a',
          segmentId: 'segment-a',
          lastActivityAt: now.subtract(const Duration(hours: 2)),
        ),
        activeSegment: const ActiveSegmentSnapshot(
          status: 'inProgress',
          isDeleted: false,
        ),
        currentSessionId: 'session-a',
        now: now,
        resumeWindow: resumeWindow,
      );

      expect(decision.shouldResume, isTrue);
      expect(decision.reason, SegmentBoundaryReason.resume);
    });

    test('starts a new segment after a different task', () {
      final decision = decideSegmentBoundary(
        previousTask: LearningTaskSnapshot(
          sessionId: 'session-b',
          segmentId: 'segment-b',
          lastActivityAt: now.subtract(const Duration(hours: 2)),
        ),
        activeSegment: const ActiveSegmentSnapshot(
          status: 'inProgress',
          isDeleted: false,
        ),
        currentSessionId: 'session-a',
        now: now,
        resumeWindow: resumeWindow,
      );

      expect(decision.shouldResume, isFalse);
      expect(decision.reason, SegmentBoundaryReason.differentTask);
    });

    test('starts a new segment when the previous segment is deleted', () {
      final decision = decideSegmentBoundary(
        previousTask: LearningTaskSnapshot(
          sessionId: 'session-a',
          segmentId: 'segment-a',
          lastActivityAt: now.subtract(const Duration(hours: 2)),
        ),
        activeSegment: const ActiveSegmentSnapshot(
          status: 'inProgress',
          isDeleted: true,
        ),
        currentSessionId: 'session-a',
        now: now,
        resumeWindow: resumeWindow,
      );

      expect(decision.shouldResume, isFalse);
      expect(
        decision.reason,
        SegmentBoundaryReason.activeSegmentDeletedOrMissing,
      );
    });

    test('starts a new segment after the resume window expires', () {
      final decision = decideSegmentBoundary(
        previousTask: LearningTaskSnapshot(
          sessionId: 'session-a',
          segmentId: 'segment-a',
          lastActivityAt: now.subtract(const Duration(hours: 25)),
        ),
        activeSegment: const ActiveSegmentSnapshot(
          status: 'inProgress',
          isDeleted: false,
        ),
        currentSessionId: 'session-a',
        now: now,
        resumeWindow: resumeWindow,
      );

      expect(decision.shouldResume, isFalse);
      expect(decision.reason, SegmentBoundaryReason.resumeWindowExpired);
    });
  });
}
