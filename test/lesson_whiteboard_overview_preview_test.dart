import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';
import 'package:my_new_app/widgets/lesson_media_playback_gate.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_overview_preview.dart';

void main() {
  testWidgets('overview preview is view-only and claims the playback gate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gate = LessonMediaPlaybackGate();
    late FakeLessonMediaPlaylistPlayback firstPlayback;
    late FakeLessonMediaPlaylistPlayback secondPlayback;
    var firstFactoryCalls = 0;
    var secondFactoryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              LessonWhiteboardOverviewPreview(
                courseId: 'course-1',
                mediaSegments: const [
                  LessonMediaSegment(
                    id: 'a',
                    order: 0,
                    mediaType: 'audio',
                    url: 'https://example.com/a.mp3',
                    durationSec: 10,
                  ),
                ],
                durationLabel: '10秒',
                boardSet: const BoardSet(
                  boards: [
                    LessonWhiteboardBoard(
                      id: LessonWhiteboardBoard.defaultBoardId,
                      order: 0,
                      layerBundle: LessonWhiteboardLayerBundle(
                        layers: [
                          LessonWhiteboardLayer(
                            id: 'primary',
                            order: 0,
                            strokes: [
                              WhiteboardStroke(
                                id: 'ink',
                                timestampSec: 0,
                                points: [
                                  WhiteboardPoint(x: 0.1, y: 0.1),
                                  WhiteboardPoint(x: 0.2, y: 0.2),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                playbackGate: gate,
                playbackOwnerId: 'first',
                playlistPlaybackFactory: () {
                  firstFactoryCalls++;
                  firstPlayback = FakeLessonMediaPlaylistPlayback(
                    totalDurationSec: 10,
                  );
                  return firstPlayback;
                },
              ),
              LessonWhiteboardOverviewPreview(
                courseId: 'course-1',
                mediaSegments: const [
                  LessonMediaSegment(
                    id: 'b',
                    order: 0,
                    mediaType: 'audio',
                    url: 'https://example.com/b.mp3',
                    durationSec: 10,
                  ),
                ],
                durationLabel: '10秒',
                boardSet: const BoardSet(),
                playbackGate: gate,
                playbackOwnerId: 'second',
                playlistPlaybackFactory: () {
                  secondFactoryCalls++;
                  secondPlayback = FakeLessonMediaPlaylistPlayback(
                    totalDurationSec: 10,
                  );
                  return secondPlayback;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(firstFactoryCalls, 1);
    expect(secondFactoryCalls, 1);
    expect(find.text('レッスン全体のプレビュー'), findsNWidgets(2));
    expect(find.text('リセット'), findsNothing);
    expect(find.text('書き物を一時保存'), findsNothing);
    expect(find.text('書き物を描き直す'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'スタート').first);
    await tester.pump();
    expect(firstPlayback.isPlaying, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'スタート').last);
    await tester.pump();
    expect(firstPlayback.isPlaying, isFalse);
    expect(secondPlayback.isPlaying, isTrue);
  });
}
