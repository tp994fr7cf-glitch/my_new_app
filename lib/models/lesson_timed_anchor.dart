import 'lesson_media_timeline.dart';

enum LessonTimedAnchorType {
  global,
  segment;

  static LessonTimedAnchorType fromStorage(String? value) {
    return value == 'segment' ? LessonTimedAnchorType.segment : LessonTimedAnchorType.global;
  }

  String toStorage() {
    return switch (this) {
      LessonTimedAnchorType.global => 'global',
      LessonTimedAnchorType.segment => 'segment',
    };
  }
}

class LessonTimedAnchor {
  const LessonTimedAnchor({
    required this.anchorType,
    required this.timestampSec,
    this.segmentId,
    this.globalTimestampSec,
  });

  final LessonTimedAnchorType anchorType;
  final int timestampSec;
  final String? segmentId;
  final int? globalTimestampSec;

  int resolveGlobalTimestampSec(LessonMediaTimeline timeline) {
    if (globalTimestampSec != null) {
      return globalTimestampSec!;
    }
    if (anchorType == LessonTimedAnchorType.segment) {
      final segmentId = this.segmentId;
      if (segmentId == null || segmentId.isEmpty) {
        return timestampSec;
      }
      return timeline
          .globalSecForSegmentLocal(
            segmentId: segmentId,
            localSec: timestampSec.toDouble(),
          )
          .round();
    }
    return timestampSec;
  }

  factory LessonTimedAnchor.fromMap(Map data) {
    return LessonTimedAnchor(
      anchorType: LessonTimedAnchorType.fromStorage(
        data['anchorType'] as String?,
      ),
      timestampSec: (data['timestampSec'] as num?)?.toInt() ?? 0,
      segmentId: data['segmentId'] as String?,
      globalTimestampSec: (data['globalTimestampSec'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'anchorType': anchorType.toStorage(),
      'timestampSec': timestampSec,
      if (segmentId != null && segmentId!.isNotEmpty) 'segmentId': segmentId,
      if (globalTimestampSec != null) 'globalTimestampSec': globalTimestampSec,
    };
  }

  LessonTimedAnchor withResolvedGlobalTimestamp(LessonMediaTimeline timeline) {
    return LessonTimedAnchor(
      anchorType: anchorType,
      timestampSec: timestampSec,
      segmentId: segmentId,
      globalTimestampSec: resolveGlobalTimestampSec(timeline),
    );
  }
}
