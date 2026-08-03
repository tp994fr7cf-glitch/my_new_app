import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/live_audio_board_selection.dart';

void main() {
  const boardSet = BoardSet(
    boards: [
      LessonWhiteboardBoard(id: 'initial', order: 0),
      LessonWhiteboardBoard(id: 'later', order: 1),
    ],
    switchEvents: [
      LessonWhiteboardBoardSwitchEvent(
        boardId: 'initial',
        globalTimestampSec: 0,
        sequence: 0,
      ),
      LessonWhiteboardBoardSwitchEvent(
        boardId: 'later',
        globalTimestampSec: 10,
        sequence: 1,
      ),
    ],
  );

  test('uses the joined session start for later-part catch-up playback', () {
    expect(
      resolveLiveAudioCatchupTimelineSec(
        fallbackSegmentStartSec: 0,
        sessionSegmentStartSec: 70.888,
        archiveTimelineOffsetSec: 1.558,
        hlsMediaTimelineOffsetSec: 2.921,
        positionSec: 4,
      ),
      closeTo(77.809, 0.000001),
    );
    expect(
      resolveLiveAudioCatchupTimelineSec(
        fallbackSegmentStartSec: 0,
        sessionSegmentStartSec: 70.888,
        archiveTimelineOffsetSec: 1.558,
        hlsMediaTimelineOffsetSec: null,
        positionSec: 4,
      ),
      closeTo(76.446, 0.000001),
    );
  });

  test('delays future whiteboard playback by the measured audio delay', () {
    expect(
      resolveLiveAudioCatchupTimelineSec(
        fallbackSegmentStartSec: 0,
        sessionSegmentStartSec: 71.785,
        archiveTimelineOffsetSec: 1.155,
        hlsMediaTimelineOffsetSec: 1.87,
        audioPlaybackCompensationSec: 1.34,
        positionSec: 4,
      ),
      closeTo(76.315, 0.000001),
    );
    expect(
      resolveLiveAudioCatchupTimelineSec(
        fallbackSegmentStartSec: 0,
        sessionSegmentStartSec: 0,
        archiveTimelineOffsetSec: 0.5,
        hlsMediaTimelineOffsetSec: 0.8,
        audioPlaybackCompensationSec: 1.2,
        positionSec: 4,
      ),
      4,
    );
  });

  test('falls back to the route start before a session is loaded', () {
    expect(
      resolveLiveAudioSegmentStartSec(
        fallbackSegmentStartSec: 30,
        sessionSegmentStartSec: null,
      ),
      30,
    );
  });

  test('exposes only boards that existed at the catch-up position', () {
    expect(
      liveAudioBoardsAvailableAt(
        boardSet: boardSet,
        globalTimestampSec: 9,
        boardsCreatedDuringSession: const {'later'},
      ).map((board) => board.id),
      ['initial'],
    );
    expect(
      liveAudioBoardsAvailableAt(
        boardSet: boardSet,
        globalTimestampSec: 10,
        boardsCreatedDuringSession: const {'later'},
      ).map((board) => board.id),
      ['initial', 'later'],
    );
  });

  test('manual catch-up selection overrides recorded board switching', () {
    expect(
      resolveLiveAudioDisplayBoardId(
        boardSet: boardSet,
        presenterBoardId: 'later',
        isCatchup: true,
        followPresenter: false,
        viewerBoardId: 'initial',
        catchupTimelineSec: 12,
        boardsCreatedDuringSession: const {'later'},
      ),
      'initial',
    );
  });

  test('rewinding before a selected board existed restores recorded board', () {
    expect(
      retainLiveAudioViewerBoardAt(
        boardSet: boardSet,
        viewerBoardId: 'later',
        globalTimestampSec: 5,
        boardsCreatedDuringSession: const {'later'},
      ),
      isNull,
    );
    expect(
      resolveLiveAudioDisplayBoardId(
        boardSet: boardSet,
        presenterBoardId: 'later',
        isCatchup: true,
        followPresenter: false,
        viewerBoardId: 'later',
        catchupTimelineSec: 5,
        boardsCreatedDuringSession: const {'later'},
      ),
      'initial',
    );
  });

  test('boards not created during this session remain available', () {
    expect(
      liveAudioBoardsAvailableAt(
        boardSet: boardSet,
        globalTimestampSec: 0,
        boardsCreatedDuringSession: const {},
      ).map((board) => board.id),
      ['initial', 'later'],
    );
  });

  test('manual board selection still hides strokes from the future', () {
    const bundle = LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(
          id: LessonWhiteboardLayer.primaryLayerId,
          order: 0,
          strokes: [
            WhiteboardStroke(
              id: 'future-stroke',
              timestampSec: 15,
              points: [
                WhiteboardPoint(x: 0, y: 0),
                WhiteboardPoint(x: 1, y: 1),
              ],
            ),
          ],
        ),
      ],
    );

    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        globalPositionSec: 12,
        segmentLocalPositionSec: 12,
      ),
      isEmpty,
    );
    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        globalPositionSec: 15,
        segmentLocalPositionSec: 15,
      ).map((stroke) => stroke.id),
      ['future-stroke'],
    );
  });
}
