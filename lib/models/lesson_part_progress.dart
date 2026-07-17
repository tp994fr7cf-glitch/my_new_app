import 'lesson_playback_mode.dart';

class LessonPartProgressEntry {
  const LessonPartProgressEntry({
    required this.segmentId,
    required this.isCompleted,
    required this.resumePositionSec,
  });

  final String segmentId;
  final bool isCompleted;
  final double resumePositionSec;
}

class LessonPartProgress {
  LessonPartProgress({
    required Iterable<String> requiredSegmentIds,
    required Iterable<String> completedSegmentIds,
    Map<String, double> resumePositionsSec = const {},
  }) : requiredSegmentIds = List.unmodifiable(
         _uniqueNonEmptyIds(requiredSegmentIds),
       ),
       completedSegmentIds = Set.unmodifiable(
         _uniqueNonEmptyIds(completedSegmentIds),
       ),
       resumePositionsSec = Map.unmodifiable({
         for (final entry in resumePositionsSec.entries)
           if (entry.key.isNotEmpty)
             entry.key: entry.value.isNegative ? 0 : entry.value,
       });

  final List<String> requiredSegmentIds;

  /// Includes completion records for parts no longer in the current lesson.
  final Set<String> completedSegmentIds;

  /// Includes saved positions for current and historical parts.
  final Map<String, double> resumePositionsSec;

  List<LessonPartProgressEntry> get currentParts {
    return [
      for (final segmentId in requiredSegmentIds)
        LessonPartProgressEntry(
          segmentId: segmentId,
          isCompleted: isPartCompleted(segmentId),
          resumePositionSec: resumePositionSecForPart(segmentId),
        ),
    ];
  }

  Set<String> get historicalCompletedSegmentIds {
    return completedSegmentIds.difference(requiredSegmentIds.toSet());
  }

  bool isPartCompleted(String segmentId) {
    return completedSegmentIds.contains(segmentId);
  }

  double resumePositionSecForPart(String segmentId) {
    if (isPartCompleted(segmentId)) {
      return 0;
    }
    return resumePositionsSec[segmentId] ?? 0;
  }

  bool get allCurrentPartsCompleted {
    return requiredSegmentIds.isNotEmpty &&
        requiredSegmentIds.every(completedSegmentIds.contains);
  }

  bool isLessonCompleted({
    required LessonPlaybackMode playbackMode,
    bool continuousLessonCompleted = false,
  }) {
    if (playbackMode.isIndependent) {
      return allCurrentPartsCompleted;
    }
    return continuousLessonCompleted;
  }

  factory LessonPartProgress.reconcile({
    required Iterable<String> requiredCurrentSegmentIds,
    required Iterable<String> completedSegmentIds,
    Map<String, double> retainedResumePositionsSec = const {},
  }) {
    return LessonPartProgress(
      requiredSegmentIds: requiredCurrentSegmentIds,
      completedSegmentIds: completedSegmentIds,
      resumePositionsSec: retainedResumePositionsSec,
    );
  }
}

LessonPartProgress reconcileLessonPartProgress({
  required Iterable<String> requiredCurrentSegmentIds,
  required Iterable<String> completedSegmentIds,
  Map<String, double> retainedResumePositionsSec = const {},
}) {
  return LessonPartProgress.reconcile(
    requiredCurrentSegmentIds: requiredCurrentSegmentIds,
    completedSegmentIds: completedSegmentIds,
    retainedResumePositionsSec: retainedResumePositionsSec,
  );
}

List<String> _uniqueNonEmptyIds(Iterable<String> ids) {
  final seen = <String>{};
  return [
    for (final id in ids)
      if (id.isNotEmpty && seen.add(id)) id,
  ];
}
