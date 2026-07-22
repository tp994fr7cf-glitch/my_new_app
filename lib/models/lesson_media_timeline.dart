import 'lesson_media_segment.dart';

class LessonMediaPosition {
  const LessonMediaPosition({
    required this.segmentIndex,
    required this.segmentId,
    required this.localSec,
    required this.globalSec,
    required this.segment,
  });

  final int segmentIndex;
  final String segmentId;
  final double localSec;
  final double globalSec;
  final LessonMediaSegment segment;
}

class LessonMediaTimeline {
  const LessonMediaTimeline({required this.segments});

  final List<LessonMediaSegment> segments;

  bool get isEmpty => orderedSegments.isEmpty;

  int get segmentCount => orderedSegments.length;

  List<LessonMediaSegment> get orderedSegments {
    return LessonMediaSegment.normalizeOrders(segments);
  }

  int get totalDurationSec {
    final exact = totalDurationSecExact;
    if (exact <= 0) {
      return 0;
    }
    return exact.floor().clamp(1, 2147483647).toInt();
  }

  double get totalDurationSecExact {
    var total = 0.0;
    for (final segment in orderedSegments) {
      total += segment.durationSecExact;
    }
    return total;
  }

  LessonMediaSegment? segmentById(String segmentId) {
    for (final segment in orderedSegments) {
      if (segment.id == segmentId) {
        return segment;
      }
    }
    return null;
  }

  int indexOfSegmentId(String segmentId) {
    final ordered = orderedSegments;
    for (var index = 0; index < ordered.length; index++) {
      if (ordered[index].id == segmentId) {
        return index;
      }
    }
    return -1;
  }

  double startGlobalSecForSegmentIndex(int segmentIndex) {
    var start = 0.0;
    final ordered = orderedSegments;
    for (var index = 0; index < ordered.length; index++) {
      if (index == segmentIndex) {
        return start;
      }
      start += ordered[index].durationSecExact;
    }
    return start;
  }

  double startGlobalSecForSegmentId(String segmentId) {
    final index = indexOfSegmentId(segmentId);
    if (index < 0) {
      return 0;
    }
    return startGlobalSecForSegmentIndex(index);
  }

  double globalSecForSegmentLocal({
    required String segmentId,
    required double localSec,
  }) {
    final segment = segmentById(segmentId);
    if (segment == null) {
      return 0;
    }
    final start = startGlobalSecForSegmentId(segmentId);
    final clampedLocal = localSec.clamp(0.0, segment.durationSecExact);
    return start + clampedLocal;
  }

  double globalSecForSegmentIndex({
    required int segmentIndex,
    required double localSec,
  }) {
    final ordered = orderedSegments;
    if (segmentIndex < 0 || segmentIndex >= ordered.length) {
      return 0;
    }
    final segment = ordered[segmentIndex];
    final clampedLocal = localSec.clamp(0.0, segment.durationSecExact);
    return startGlobalSecForSegmentIndex(segmentIndex) + clampedLocal;
  }

  LessonMediaPosition resolveGlobalSec(double globalSec) {
    final ordered = orderedSegments;
    if (ordered.isEmpty) {
      throw StateError('Cannot resolve position on an empty timeline.');
    }

    final clampedGlobal = globalSec.clamp(0.0, totalDurationSecExact);
    var cursor = 0.0;
    for (var index = 0; index < ordered.length; index++) {
      final segment = ordered[index];
      final segmentDuration = segment.durationSecExact;
      final segmentEnd = cursor + segmentDuration;
      final isLastSegment = index == ordered.length - 1;
      if (clampedGlobal < segmentEnd || isLastSegment) {
        final localSec = (clampedGlobal - cursor).clamp(0.0, segmentDuration);
        return LessonMediaPosition(
          segmentIndex: index,
          segmentId: segment.id,
          localSec: localSec,
          globalSec: cursor + localSec,
          segment: segment,
        );
      }
      cursor = segmentEnd;
    }

    final lastIndex = ordered.length - 1;
    final lastSegment = ordered[lastIndex];
    return LessonMediaPosition(
      segmentIndex: lastIndex,
      segmentId: lastSegment.id,
      localSec: lastSegment.durationSecExact,
      globalSec: totalDurationSecExact,
      segment: lastSegment,
    );
  }
}
