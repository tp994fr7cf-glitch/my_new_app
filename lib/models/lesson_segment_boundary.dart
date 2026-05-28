enum SegmentBoundaryReason {
  resume,
  noPreviousTask,
  differentTask,
  resumeWindowExpired,
  activeSegmentDeletedOrMissing,
}

class LearningTaskSnapshot {
  const LearningTaskSnapshot({
    required this.sessionId,
    required this.segmentId,
    required this.lastActivityAt,
  });

  final String sessionId;
  final String segmentId;
  final DateTime? lastActivityAt;
}

class ActiveSegmentSnapshot {
  const ActiveSegmentSnapshot({required this.status, required this.isDeleted});

  final String? status;
  final bool isDeleted;
}

class SegmentBoundaryDecision {
  const SegmentBoundaryDecision({
    required this.shouldResume,
    required this.reason,
  });

  final bool shouldResume;
  final SegmentBoundaryReason reason;
}

SegmentBoundaryDecision decideSegmentBoundary({
  required LearningTaskSnapshot? previousTask,
  required ActiveSegmentSnapshot? activeSegment,
  required String currentSessionId,
  required DateTime now,
  required Duration resumeWindow,
}) {
  if (previousTask == null) {
    return const SegmentBoundaryDecision(
      shouldResume: false,
      reason: SegmentBoundaryReason.noPreviousTask,
    );
  }

  if (previousTask.sessionId != currentSessionId) {
    return const SegmentBoundaryDecision(
      shouldResume: false,
      reason: SegmentBoundaryReason.differentTask,
    );
  }

  final lastActivityAt = previousTask.lastActivityAt;
  final elapsedSinceLastActivity = lastActivityAt == null
      ? null
      : now.difference(lastActivityAt);
  if (elapsedSinceLastActivity == null ||
      (!elapsedSinceLastActivity.isNegative &&
          elapsedSinceLastActivity >= resumeWindow)) {
    return const SegmentBoundaryDecision(
      shouldResume: false,
      reason: SegmentBoundaryReason.resumeWindowExpired,
    );
  }

  if (activeSegment == null ||
      activeSegment.status != 'inProgress' ||
      activeSegment.isDeleted) {
    return const SegmentBoundaryDecision(
      shouldResume: false,
      reason: SegmentBoundaryReason.activeSegmentDeletedOrMissing,
    );
  }

  return const SegmentBoundaryDecision(
    shouldResume: true,
    reason: SegmentBoundaryReason.resume,
  );
}

String segmentBoundaryReasonName(SegmentBoundaryReason reason) {
  return switch (reason) {
    SegmentBoundaryReason.resume => 'resume',
    SegmentBoundaryReason.noPreviousTask => 'noPreviousTask',
    SegmentBoundaryReason.differentTask => 'differentTask',
    SegmentBoundaryReason.resumeWindowExpired => 'resumeWindowExpired',
    SegmentBoundaryReason.activeSegmentDeletedOrMissing =>
      'activeSegmentDeletedOrMissing',
  };
}
