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
           if (_isUsableId(entry.key) && entry.value.isFinite)
             entry.key: entry.value.isNegative ? 0 : entry.value,
       });

  final List<String> requiredSegmentIds;

  /// Includes completion records for parts no longer in the current lesson.
  final Set<String> completedSegmentIds;

  /// Includes saved positions for current and historical parts.
  final Map<String, double> resumePositionsSec;

  /// Historical completion IDs remain persisted so append-only publication
  /// can distinguish an old completed prefix from a newly appended part.
  List<String> get completedSegmentIdsForPersistence =>
      completedSegmentIds.where(_isUsableId).toList();

  /// Resume positions are useful only for incomplete parts in the current
  /// publication. Dropping stale positions bounds document growth without
  /// deleting historical completion evidence.
  Map<String, double> get resumePositionsSecForPersistence => {
    for (final segmentId in requiredSegmentIds)
      if (!completedSegmentIds.contains(segmentId) &&
          resumePositionsSec.containsKey(segmentId) &&
          resumePositionsSec[segmentId]!.isFinite)
        segmentId: resumePositionsSec[segmentId]!.isNegative
            ? 0
            : resumePositionsSec[segmentId]!,
  };

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

  factory LessonPartProgress.fromSessionData({
    required Map data,
    required Iterable<String> requiredCurrentSegmentIds,
  }) {
    final currentIds = _uniqueNonEmptyIds(requiredCurrentSegmentIds);
    final storedRequiredIds = parseLessonSessionSegmentIds(
      data['requiredMediaSegmentIds'],
    );
    final allowedCompletionIds = <String>{...currentIds, ...storedRequiredIds};
    final completedIds = parseLessonSessionSegmentIds(
      data['completedMediaSegmentIds'],
    ).where(allowedCompletionIds.contains);
    final parsedResumePositions = parseLessonSessionResumePositions(
      data['mediaSegmentResumePositionsSec'],
    );
    return LessonPartProgress(
      requiredSegmentIds: currentIds,
      completedSegmentIds: completedIds,
      resumePositionsSec: {
        for (final id in currentIds)
          if (parsedResumePositions.containsKey(id))
            id: parsedResumePositions[id]!,
      },
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
      if (_isUsableId(id) && seen.add(id)) id,
  ];
}

Set<String> parseLessonSessionSegmentIds(Object? value) {
  return value is List
      ? value.whereType<String>().where(_isUsableId).toSet()
      : <String>{};
}

Map<String, double> parseLessonSessionResumePositions(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String &&
          _isUsableId(entry.key as String) &&
          entry.value is num &&
          (entry.value as num).toDouble().isFinite)
        entry.key as String: (entry.value as num).toDouble().isNegative
            ? 0
            : (entry.value as num).toDouble(),
  };
}

/// Interprets both legacy whole-lesson completion and part-aware sessions.
///
/// A legacy independent session has no part metadata, so its old completion
/// flag remains authoritative. Once either part field exists, completion is
/// reconciled against the lesson's current published parts. This intentionally
/// reopens a completed cycle when a new part is appended.
bool lessonSessionRepresentsCompleted({
  required Map data,
  required LessonPlaybackMode playbackMode,
  required Iterable<String> requiredCurrentSegmentIds,
}) {
  final legacyCompleted =
      data['status'] == 'completed' || data['cycleCompleted'] == true;
  if (!playbackMode.isIndependent) {
    return legacyCompleted;
  }
  if (!data.containsKey('completedMediaSegmentIds') &&
      !data.containsKey('requiredMediaSegmentIds')) {
    return legacyCompleted;
  }

  final progress = LessonPartProgress.fromSessionData(
    data: data,
    requiredCurrentSegmentIds: requiredCurrentSegmentIds,
  );
  return progress.allCurrentPartsCompleted;
}

Object? firstLessonCompletionTimestamp(Map data) {
  return data['firstCompletedAt'] ?? data['completedAt'];
}

bool _isUsableId(String id) => id.trim().isNotEmpty;
