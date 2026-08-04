import 'lesson_media_timeline.dart';

const double _whiteboardBoundaryEpsilonSec = 0.000001;

class LessonWhiteboardPlaybackLookup {
  const LessonWhiteboardPlaybackLookup({
    required this.playbackGlobalSec,
    required this.globalSec,
    required this.segmentLocalSec,
    required this.segmentId,
    required this.correctionSec,
  });

  final double playbackGlobalSec;
  final double globalSec;
  final double segmentLocalSec;
  final String? segmentId;
  final double correctionSec;
}

double resolveLessonWhiteboardCorrectionSec({
  required int startCorrectionMs,
  required int endCorrectionMs,
  required double segmentLocalSec,
  required double segmentDurationSec,
}) {
  if (segmentDurationSec <= 0) {
    return startCorrectionMs / 1000;
  }
  final progress = (segmentLocalSec / segmentDurationSec).clamp(0.0, 1.0);
  final correctionMs =
      startCorrectionMs + (endCorrectionMs - startCorrectionMs) * progress;
  return correctionMs / 1000;
}

LessonWhiteboardPlaybackLookup resolveLessonWhiteboardPlaybackLookup({
  required double playbackGlobalSec,
  required LessonMediaTimeline timeline,
}) {
  if (timeline.isEmpty) {
    return LessonWhiteboardPlaybackLookup(
      playbackGlobalSec: playbackGlobalSec,
      globalSec: playbackGlobalSec,
      segmentLocalSec: playbackGlobalSec,
      segmentId: null,
      correctionSec: 0,
    );
  }

  final mediaPosition = timeline.resolveGlobalSec(playbackGlobalSec);
  final segment = mediaPosition.segment;
  final durationSec = segment.durationSecExact;
  final segmentStartSec = timeline.startGlobalSecForSegmentIndex(
    mediaPosition.segmentIndex,
  );
  final segmentEndSec = segmentStartSec + durationSec;
  final correctionSec = resolveLessonWhiteboardCorrectionSec(
    startCorrectionMs: segment.whiteboardStartCorrectionMs,
    endCorrectionMs: segment.whiteboardEndCorrectionMs,
    segmentLocalSec: mediaPosition.localSec,
    segmentDurationSec: durationSec,
  );
  final rawLocalSec = mediaPosition.localSec + correctionSec;
  final rawGlobalSec = segmentStartSec + rawLocalSec;
  final hasNextSegment = mediaPosition.segmentIndex + 1 < timeline.segmentCount;

  final globalSec = switch (rawGlobalSec) {
    < 0 when segmentStartSec == 0 => -_whiteboardBoundaryEpsilonSec,
    _ when rawGlobalSec < segmentStartSec =>
      segmentStartSec - _whiteboardBoundaryEpsilonSec,
    _ when hasNextSegment && rawGlobalSec >= segmentEndSec =>
      segmentEndSec - _whiteboardBoundaryEpsilonSec,
    _ when rawGlobalSec > segmentEndSec => segmentEndSec,
    _ => rawGlobalSec,
  };
  final localSec = rawLocalSec > durationSec ? durationSec : rawLocalSec;

  return LessonWhiteboardPlaybackLookup(
    playbackGlobalSec: mediaPosition.globalSec,
    globalSec: globalSec,
    segmentLocalSec: localSec,
    segmentId: mediaPosition.segmentId,
    correctionSec: correctionSec,
  );
}
