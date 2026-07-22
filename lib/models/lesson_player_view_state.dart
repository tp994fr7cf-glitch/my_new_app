import 'lesson_media_segment.dart';

enum LessonPlayButtonVisual { play, pause, replay }

bool lessonHasMediaSource(String mediaUrl) => mediaUrl.trim().isNotEmpty;

bool lessonHasPlayableMedia({
  required List<LessonMediaSegment> mediaSegments,
}) => lessonHasMediaSegments(mediaSegments);

/// Returns true when playback has reached (or passed) the lesson end.
///
/// Uses [positionSecExact] with a small tolerance so natural stops slightly
/// before the integer second boundary (common on web audio) still count as end.
bool isLessonPlaybackAtEnd({
  required num totalDurationSec,
  required double positionSecExact,
  double endToleranceSec = 0.5,
}) {
  final totalDurationSecExact = totalDurationSec.toDouble();
  if (totalDurationSecExact <= 0) {
    return false;
  }
  if (positionSecExact >= totalDurationSecExact - endToleranceSec) {
    return true;
  }
  return positionSecExact >= totalDurationSecExact;
}

String formatLessonTime(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}

LessonPlayButtonVisual lessonPlayButtonVisual({
  required bool isPlaying,
  required bool isAtEnd,
}) {
  if (isPlaying) {
    return LessonPlayButtonVisual.pause;
  }
  if (isAtEnd) {
    return LessonPlayButtonVisual.replay;
  }
  return LessonPlayButtonVisual.play;
}

String lessonPlayButtonLabel({
  required bool isPreparingSession,
  required bool isPlaying,
  required bool isSessionCompleted,
  required bool isAtEnd,
}) {
  if (isPreparingSession) {
    return '準備中';
  }
  if (isPlaying) {
    return '一時停止';
  }
  if (isSessionCompleted || isAtEnd) {
    return 'もう一度再生';
  }
  return '再生';
}
