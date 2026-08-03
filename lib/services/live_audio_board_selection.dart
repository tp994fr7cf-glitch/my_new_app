import '../models/lesson_whiteboard_board_set.dart';

double resolveLiveAudioSegmentStartSec({
  required double fallbackSegmentStartSec,
  required double? sessionSegmentStartSec,
}) {
  final sessionValue = sessionSegmentStartSec;
  if (sessionValue != null && sessionValue.isFinite && sessionValue >= 0) {
    return sessionValue;
  }
  return fallbackSegmentStartSec;
}

double resolveLiveAudioCatchupTimelineSec({
  required double fallbackSegmentStartSec,
  required double? sessionSegmentStartSec,
  required double archiveTimelineOffsetSec,
  required double? hlsMediaTimelineOffsetSec,
  double audioPlaybackCompensationSec = 0,
  required double positionSec,
}) {
  final timelineOffsetSec =
      hlsMediaTimelineOffsetSec ?? archiveTimelineOffsetSec;
  final safeCompensationSec =
      audioPlaybackCompensationSec.isFinite && audioPlaybackCompensationSec >= 0
      ? audioPlaybackCompensationSec
      : 0;
  // HLS audio begins after the session clock, and the measured capture-to-HLS
  // delay is subtracted so board visibility is delayed to match that audio.
  // The finalized-lesson path applies the same sign in Functions. If a
  // reproduced bug requires adjustment, test catch-up and published playback
  // together instead of changing only one side.
  return resolveLiveAudioSegmentStartSec(
        fallbackSegmentStartSec: fallbackSegmentStartSec,
        sessionSegmentStartSec: sessionSegmentStartSec,
      ) +
      (timelineOffsetSec - safeCompensationSec)
          .clamp(0.0, double.infinity)
          .toDouble() +
      positionSec;
}

String resolveLiveAudioDisplayBoardId({
  required BoardSet boardSet,
  required String presenterBoardId,
  required bool isCatchup,
  required bool followPresenter,
  required String? viewerBoardId,
  required double catchupTimelineSec,
  required Set<String> boardsCreatedDuringSession,
}) {
  if (!isCatchup) {
    return followPresenter
        ? presenterBoardId
        : (viewerBoardId ?? presenterBoardId);
  }

  final retainedViewerBoardId = retainLiveAudioViewerBoardAt(
    boardSet: boardSet,
    viewerBoardId: viewerBoardId,
    globalTimestampSec: catchupTimelineSec,
    boardsCreatedDuringSession: boardsCreatedDuringSession,
  );
  if (!followPresenter && retainedViewerBoardId != null) {
    return retainedViewerBoardId;
  }

  final recordedBoard = boardSet.resolveBoardAt(catchupTimelineSec);
  if (recordedBoard != null &&
      liveAudioBoardExistsAt(
        boardSet: boardSet,
        boardId: recordedBoard.id,
        globalTimestampSec: catchupTimelineSec,
        boardsCreatedDuringSession: boardsCreatedDuringSession,
      )) {
    return recordedBoard.id;
  }

  final availableBoards = liveAudioBoardsAvailableAt(
    boardSet: boardSet,
    globalTimestampSec: catchupTimelineSec,
    boardsCreatedDuringSession: boardsCreatedDuringSession,
  );
  return availableBoards.isNotEmpty
      ? availableBoards.first.id
      : presenterBoardId;
}

String? retainLiveAudioViewerBoardAt({
  required BoardSet boardSet,
  required String? viewerBoardId,
  required double globalTimestampSec,
  required Set<String> boardsCreatedDuringSession,
}) {
  if (viewerBoardId == null) {
    return null;
  }
  return liveAudioBoardExistsAt(
        boardSet: boardSet,
        boardId: viewerBoardId,
        globalTimestampSec: globalTimestampSec,
        boardsCreatedDuringSession: boardsCreatedDuringSession,
      )
      ? viewerBoardId
      : null;
}

List<LessonWhiteboardBoard> liveAudioBoardsAvailableAt({
  required BoardSet boardSet,
  required double globalTimestampSec,
  required Set<String> boardsCreatedDuringSession,
}) {
  return boardSet.orderedBoards
      .where(
        (board) => liveAudioBoardExistsAt(
          boardSet: boardSet,
          boardId: board.id,
          globalTimestampSec: globalTimestampSec,
          boardsCreatedDuringSession: boardsCreatedDuringSession,
        ),
      )
      .toList(growable: false);
}

bool liveAudioBoardExistsAt({
  required BoardSet boardSet,
  required String boardId,
  required double globalTimestampSec,
  required Set<String> boardsCreatedDuringSession,
}) {
  if (boardSet.boardById(boardId) == null) {
    return false;
  }
  if (!boardsCreatedDuringSession.contains(boardId)) {
    return true;
  }
  for (final event in boardSet.orderedSwitchEvents) {
    if (event.boardId == boardId) {
      return event.globalTimestampSec <= globalTimestampSec;
    }
  }
  return false;
}
