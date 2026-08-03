import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_player_view_state.dart';

void main() {
  group('lesson player view state', () {
    test('formats seconds as mm:ss', () {
      expect(formatLessonTime(0), '00:00');
      expect(formatLessonTime(65), '01:05');
    });

    test('detects playback end with exact position tolerance', () {
      expect(
        isLessonPlaybackAtEnd(totalDurationSec: 90, positionSecExact: 89.4),
        isFalse,
      );
      expect(
        isLessonPlaybackAtEnd(totalDurationSec: 90, positionSecExact: 89.6),
        isTrue,
      );
      expect(
        isLessonPlaybackAtEnd(totalDurationSec: 90, positionSecExact: 90),
        isTrue,
      );
    });

    test('selects play button visuals', () {
      expect(
        lessonPlayButtonVisual(isPlaying: true, isAtEnd: false),
        LessonPlayButtonVisual.pause,
      );
      expect(
        lessonPlayButtonVisual(isPlaying: false, isAtEnd: true),
        LessonPlayButtonVisual.replay,
      );
      expect(
        lessonPlayButtonVisual(isPlaying: false, isAtEnd: false),
        LessonPlayButtonVisual.play,
      );
    });

    test('detects whether lesson has media source', () {
      expect(lessonHasMediaSource(''), isFalse);
      expect(lessonHasMediaSource('   '), isFalse);
      expect(
        lessonHasMediaSource('https://example.com/lesson-count-90.mp3'),
        isTrue,
      );
    });

    test('selects play button labels', () {
      expect(
        lessonPlayButtonLabel(
          isPreparingSession: true,
          isPlaying: false,
          isSessionCompleted: false,
          isAtEnd: false,
        ),
        '準備中',
      );
      expect(
        lessonPlayButtonLabel(
          isPreparingSession: false,
          isPlaying: true,
          isSessionCompleted: false,
          isAtEnd: false,
        ),
        '一時停止',
      );
      expect(
        lessonPlayButtonLabel(
          isPreparingSession: false,
          isPlaying: false,
          isSessionCompleted: true,
          isAtEnd: false,
        ),
        'もう一度再生',
      );
      expect(
        lessonPlayButtonLabel(
          isPreparingSession: false,
          isPlaying: false,
          isSessionCompleted: false,
          isAtEnd: false,
        ),
        '再生',
      );
    });
  });
}
