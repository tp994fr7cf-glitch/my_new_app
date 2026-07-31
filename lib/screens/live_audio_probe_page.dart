import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../models/lesson_payload_size_validator.dart';
import '../services/live_audio_board_state.dart';
import '../services/live_audio_catchup_playback.dart';
import '../services/live_audio_probe_message.dart';
import '../services/live_audio_probe_rtc.dart';
import '../services/live_audio_probe_service.dart';
import '../widgets/lesson_whiteboard_canvas.dart';

const bool liveAudioProbeEnabled = bool.fromEnvironment(
  'ENABLE_LIVE_AUDIO',
  defaultValue: bool.fromEnvironment('ENABLE_AGORA_PROBE', defaultValue: false),
);

class LiveAudioProbePage extends StatefulWidget {
  const LiveAudioProbePage({
    super.key,
    required this.user,
    required this.activeRole,
    this.service,
    this.courseId,
    this.lessonId,
    this.segmentId,
    this.onSessionCreated,
    this.initialSessionId,
    this.initialBoardSet,
    this.segmentStartSec = 0,
  });

  final User user;
  final String activeRole;
  final LiveAudioProbeService? service;
  final String? courseId;
  final String? lessonId;
  final String? segmentId;
  final ValueChanged<String>? onSessionCreated;
  final String? initialSessionId;
  final BoardSet? initialBoardSet;
  final double segmentStartSec;

  @override
  State<LiveAudioProbePage> createState() => _LiveAudioProbePageState();
}

class _LiveAudioProbePageState extends State<LiveAudioProbePage> {
  late final LiveAudioProbeService _service =
      widget.service ?? LiveAudioProbeService();
  final _sessionCodeController = TextEditingController();
  final _clock = Stopwatch();
  final Set<String> _presenterUpdates = {};
  final Set<String> _processedTimelineEvents = {};
  final List<LiveAudioProbeMessage> _pendingTimelineMessages = [];
  LiveAudioBoardState _boardState = LiveAudioBoardState.initial();
  late final LiveAudioCatchupPlayback _catchup = LiveAudioCatchupPlayback();

  LiveAudioProbeRtcController? _rtc;
  StreamSubscription<LiveAudioProbeRtcStatus>? _statusSubscription;
  StreamSubscription<LiveAudioProbeMessage>? _messageSubscription;
  StreamSubscription<LiveAudioProbeSession>? _sessionSubscription;
  StreamSubscription<List<LiveAudioProbeParticipant>>?
  _participantsSubscription;
  StreamSubscription<List<LiveAudioSavedStroke>>? _savedStrokesSubscription;
  StreamSubscription<List<LiveAudioTimelineChunk>>? _timelineSubscription;
  StreamSubscription<LiveAudioCatchupStatus>? _catchupSubscription;
  LiveAudioProbeSession? _session;
  List<LiveAudioProbeParticipant> _participants = const [];
  LiveAudioProbePermission? _permission;
  LiveAudioProbeRtcState _rtcState = LiveAudioProbeRtcState.idle;
  WhiteboardStroke? _localStroke;
  String? _localStrokeBoardId;
  String? _viewerBoardId;
  LessonWhiteboardViewport? _viewerViewport;
  bool _followPresenter = true;
  int _viewportInteractionId = 0;
  DateTime? _lastViewportSentAt;
  int _timelineSequence = 0;
  Timer? _timelineFlushTimer;
  Timer? _snapshotSaveTimer;
  Timer? _archiveRefreshTimer;
  LiveAudioCatchupStatus _catchupStatus = const LiveAudioCatchupStatus(
    state: LiveAudioCatchupState.live,
  );
  double? _catchupSeekSec;
  bool _busy = false;
  bool _microphoneMuted = false;
  bool _applyingPermission = false;
  bool _leaving = false;
  String? _message;
  String _participantHlsManifestUrl = '';
  double _archiveAvailableDurationSec = 0;

  bool get _isTeacher => widget.activeRole == 'teacher';
  bool get _isOwner => _session?.ownerUid == widget.user.uid;
  bool get _isConnected =>
      _rtcState == LiveAudioProbeRtcState.connected ||
      _rtcState == LiveAudioProbeRtcState.reconnecting;
  bool get _canPublish => _permission?.canPublish == true;
  String? get _sessionId => _session?.id;
  bool get _isCatchup =>
      _catchupStatus.state == LiveAudioCatchupState.catchup ||
      _catchupStatus.state == LiveAudioCatchupState.loading;
  String get _displayBoardId {
    if (_isCatchup) {
      return _boardState.boardSet.resolveBoardAt(_catchupTimelineSec)?.id ??
          _boardState.selectedBoardId;
    }
    return _canPublish || _followPresenter
        ? _boardState.selectedBoardId
        : (_viewerBoardId ?? _boardState.selectedBoardId);
  }

  LessonWhiteboardBoard get _displayBoard =>
      _boardState.boardSet.boardById(_displayBoardId) ??
      _boardState.selectedBoard;
  LessonWhiteboardViewport get _displayViewport {
    if (!_canPublish && !_followPresenter && _viewerViewport != null) {
      return _viewerViewport!;
    }
    final playbackSec = _isCatchup ? _catchupTimelineSec : double.infinity;
    return _boardState.boardSet.resolveViewportAt(
      boardId: _displayBoard.id,
      globalTimestampSec: playbackSec,
    );
  }

  @override
  void initState() {
    super.initState();
    _sessionCodeController.text = widget.initialSessionId ?? '';
    if (widget.initialBoardSet?.isNotEmpty == true) {
      _boardState = LiveAudioBoardState.fromBoardSet(
        widget.initialBoardSet!,
        selectedAtSec: widget.segmentStartSec,
      );
    }
    _catchupSubscription = _catchup.statuses.listen((status) {
      if (!mounted) {
        return;
      }
      setState(() {
        _catchupStatus = status;
        if (status.state == LiveAudioCatchupState.catchup) {
          _catchupSeekSec = status.positionSec;
        }
        if (status.message != null) {
          _message = status.message;
        }
      });
    });
  }

  @override
  void dispose() {
    _sessionCodeController.dispose();
    _timelineFlushTimer?.cancel();
    _snapshotSaveTimer?.cancel();
    _cancelSubscriptions();
    unawaited(_catchupSubscription?.cancel());
    unawaited(_catchup.dispose());
    final rtc = _rtc;
    _rtc = null;
    if (rtc != null) {
      unawaited(rtc.dispose());
    }
    super.dispose();
  }

  Future<void> _createAndJoin() async {
    await _runBusy(() async {
      final sessionId = await _service.createSession(
        courseId: widget.courseId,
        lessonId: widget.lessonId,
        segmentId: widget.segmentId,
        initialBoardSet: _boardState.boardSet,
        segmentStartSec: widget.segmentStartSec,
      );
      _sessionCodeController.text = sessionId;
      widget.onSessionCreated?.call(sessionId);
      await _connect(sessionId);
    });
  }

  Future<void> _joinEnteredSession() async {
    final sessionId = _sessionCodeController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(sessionId)) {
      setState(() => _message = '20文字の配信コードを入力してください。');
      return;
    }
    await _runBusy(() => _connect(sessionId));
  }

  Future<void> _connect(String sessionId) async {
    await _leaveRtcOnly();
    final credentials = await _service.issueToken(sessionId);
    if (!mounted) {
      return;
    }
    _permission = credentials.permission;
    _participantHlsManifestUrl = credentials.hlsManifestUrl;
    final rtc = LiveAudioProbeRtcController(
      refreshToken: () => _service.issueToken(sessionId),
    );
    _rtc = rtc;
    _statusSubscription = rtc.statuses.listen((status) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rtcState = status.state;
        if (status.message != null) {
          _message = status.message;
        }
      });
    });
    _messageSubscription = rtc.messages.listen(_applyRemoteMessage);
    _sessionSubscription = _service.watchSession(sessionId).listen((session) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        if (_pendingTimelineMessages.isEmpty &&
            session.timelineNextSequence > _timelineSequence) {
          _timelineSequence = session.timelineNextSequence;
        }
        if (session.boardSet.isNotEmpty) {
          _rememberBoardSetTimelineEvents(session.boardSet);
          _boardState = _boardState.replaceSnapshot(session.boardSet);
        }
        if (session.archiveError.isNotEmpty) {
          _message = session.archiveError;
        }
      });
      if (!session.isActive) {
        setState(
          () => _message = session.isFinalizing
              ? '配信は終了しました。アーカイブを確定しています。'
              : '先生が配信を終了しました。',
        );
        unawaited(_leaveRtcOnly());
      }
    }, onError: (Object error) => _showError(error));
    _participantsSubscription = _service.watchParticipants(sessionId).listen((
      participants,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _participants = participants);
      final own = participants
          .where((participant) => participant.uid == widget.user.uid)
          .firstOrNull;
      if (own != null &&
          own.permission != _permission &&
          !_applyingPermission) {
        unawaited(_applyPermissionChange(sessionId));
      }
    }, onError: (Object error) => _showError(error));
    _savedStrokesSubscription = _service
        .watchSavedBoardStrokes(sessionId)
        .listen((records) {
          if (!mounted) {
            return;
          }
          setState(() {
            for (final record in records) {
              _boardState = _boardState.markStrokeSaved(
                boardId: record.boardId,
                stroke: record.stroke,
              );
            }
          });
        }, onError: (Object error) => _showError(error));
    _timelineSubscription = _service.watchTimelineChunks(sessionId).listen((
      chunks,
    ) {
      if (!mounted) {
        return;
      }
      for (final chunk in chunks) {
        for (final message in chunk.messages) {
          final key = _timelineEventKey(message);
          if (_processedTimelineEvents.add(key)) {
            _applyRemoteMessage(message, rememberTimelineEvent: false);
          }
        }
      }
    }, onError: (Object error) => _showError(error));
    _clock
      ..reset()
      ..start();
    _timelineFlushTimer?.cancel();
    _timelineFlushTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_flushTimelineMessages()),
    );
    await rtc.join(credentials);
    _archiveRefreshTimer?.cancel();
    _archiveRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_refreshArchiveStatus(sessionId)),
    );
    unawaited(_refreshArchiveStatus(sessionId));
    if (mounted && credentials.permission.canPublish) {
      _announceCurrentBoardState();
    }
  }

  Future<void> _applyPermissionChange(String sessionId) async {
    final rtc = _rtc;
    if (rtc == null || _applyingPermission) {
      return;
    }
    _applyingPermission = true;
    try {
      final credentials = await _service.issueToken(sessionId);
      await rtc.applyCredentials(credentials);
      if (!mounted) {
        return;
      }
      setState(() {
        _permission = credentials.permission;
        _participantHlsManifestUrl = credentials.hlsManifestUrl;
        _microphoneMuted = false;
        _message = credentials.permission.canPublish
            ? '先生から発表を許可されました。マイクと板書を利用できます。'
            : '発表を終了し、視聴専用へ戻りました。';
        if (!credentials.permission.canPublish) {
          _cancelLocalStroke();
        }
      });
      if (credentials.permission.canPublish) {
        _announceCurrentBoardState();
      }
    } catch (error) {
      _showError(error);
    } finally {
      _applyingPermission = false;
    }
  }

  Future<void> _refreshArchiveStatus(String sessionId) async {
    try {
      final status = await _service.refreshArchiveStatus(sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        if (status.hlsManifestUrl.isNotEmpty) {
          _participantHlsManifestUrl = status.hlsManifestUrl;
        }
        _archiveAvailableDurationSec = status.hlsAvailableDurationSec;
        if (status.archiveError.isNotEmpty) {
          _message = status.archiveError;
        }
      });
    } catch (_) {
      // 録音の準備中や一時的なquery失敗ではライブ配信を止めない。
    }
  }

  Future<void> _togglePresenter(
    LiveAudioProbeParticipant participant,
    bool enabled,
  ) async {
    final sessionId = _sessionId;
    if (sessionId == null || _presenterUpdates.contains(participant.uid)) {
      return;
    }
    setState(() => _presenterUpdates.add(participant.uid));
    try {
      await _service.setPresenter(
        sessionId: sessionId,
        participantUid: participant.uid,
        enabled: enabled,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _presenterUpdates.remove(participant.uid));
      }
    }
  }

  Future<void> _toggleMicrophone() async {
    final rtc = _rtc;
    if (rtc == null || !_canPublish) {
      return;
    }
    final nextMuted = !_microphoneMuted;
    try {
      await rtc.setMicrophoneMuted(nextMuted);
      if (mounted) {
        setState(() => _microphoneMuted = nextMuted);
      }
    } catch (error) {
      _showError(error);
    }
  }

  double get _currentSessionSec {
    final startedAtMs = _session?.startedAtMs ?? 0;
    if (startedAtMs > 0) {
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAtMs;
      return elapsedMs <= 0 ? 0 : elapsedMs / 1000;
    }
    return _clock.elapsedMicroseconds / 1000000;
  }

  double get _currentTimelineSec => widget.segmentStartSec + _currentSessionSec;

  double get _catchupTimelineSec =>
      widget.segmentStartSec +
      (_session?.archiveTimelineOffsetSec ?? 0) +
      _catchupStatus.positionSec;

  void _startLocalStroke() {
    if (!_canPublish || !_isConnected) {
      return;
    }
    final timestamp = _currentTimelineSec;
    final boardId = _boardState.selectedBoardId;
    final stroke = WhiteboardStroke(
      id: '${widget.user.uid}_${DateTime.now().microsecondsSinceEpoch}',
      timestampSec: timestamp,
      points: const [],
    );
    setState(() {
      _localStroke = stroke;
      _localStrokeBoardId = boardId;
    });
    _sendWhiteboardMessage(
      LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.strokeStart,
        strokeId: stroke.id,
        boardId: boardId,
        timestampSec: timestamp,
      ),
    );
  }

  void _updateLocalStroke(WhiteboardPoint point) {
    final stroke = _localStroke;
    if (stroke == null || !_canPublish) {
      return;
    }
    final timestamp = _currentTimelineSec;
    final timedPoint = WhiteboardPoint(
      x: point.x,
      y: point.y,
      timestampSec: timestamp,
    );
    if (!shouldSampleWhiteboardPoint(
      existingPoints: stroke.points,
      nextPoint: timedPoint,
      nextTimestampSec: timestamp,
      force: false,
    )) {
      return;
    }
    final next = stroke.copyWith(points: [...stroke.points, timedPoint]);
    setState(() => _localStroke = next);
    _sendWhiteboardMessage(
      LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.strokePoint,
        strokeId: next.id,
        boardId: _localStrokeBoardId ?? LessonWhiteboardBoard.defaultBoardId,
        timestampSec: timestamp,
        point: timedPoint,
      ),
    );
  }

  void _endLocalStroke(WhiteboardPoint point) {
    final stroke = _localStroke;
    if (stroke == null || !_canPublish) {
      return;
    }
    final timestamp = _currentTimelineSec;
    final boardId = _localStrokeBoardId ?? LessonWhiteboardBoard.defaultBoardId;
    final timedPoint = WhiteboardPoint(
      x: point.x,
      y: point.y,
      timestampSec: timestamp,
    );
    final points =
        shouldSampleWhiteboardPoint(
          existingPoints: stroke.points,
          nextPoint: timedPoint,
          nextTimestampSec: timestamp,
          force: true,
        )
        ? [...stroke.points, timedPoint]
        : stroke.points;
    final completed = WhiteboardStroke(
      id: stroke.id,
      timestampSec: stroke.timestampSec,
      endTimestampSec: timestamp,
      points: points,
      colorArgb: stroke.colorArgb,
      strokeWidth: stroke.strokeWidth,
    );
    setState(() {
      _localStroke = null;
      _localStrokeBoardId = null;
      _boardState = _boardState.saveCompletedStroke(
        boardId: boardId,
        stroke: completed,
      );
    });
    _sendWhiteboardMessage(
      LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.strokeEnd,
        strokeId: completed.id,
        boardId: boardId,
        timestampSec: timestamp,
        point: timedPoint,
      ),
    );
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(
        _service
            .saveStroke(
              sessionId: sessionId,
              boardId: boardId,
              stroke: completed,
            )
            .catchError(_showError),
      );
      _scheduleSnapshotSave();
    }
  }

  void _cancelLocalStroke() {
    _localStroke = null;
    _localStrokeBoardId = null;
  }

  void _applyRemoteMessage(
    LiveAudioProbeMessage message, {
    bool rememberTimelineEvent = true,
  }) {
    if (!mounted) {
      return;
    }
    if (rememberTimelineEvent &&
        (message.kind == LiveAudioProbeMessageKind.boardCreate ||
            message.kind == LiveAudioProbeMessageKind.boardSwitch ||
            message.kind == LiveAudioProbeMessageKind.viewport) &&
        !_processedTimelineEvents.add(_timelineEventKey(message))) {
      return;
    }
    setState(() {
      _boardState = _boardState.applyMessage(
        message,
        localStrokeId: _localStroke?.id,
      );
      if (_followPresenter &&
          (message.kind == LiveAudioProbeMessageKind.boardSwitch ||
              message.kind == LiveAudioProbeMessageKind.viewport)) {
        _viewerBoardId = null;
        _viewerViewport = null;
      }
    });
  }

  void _rememberBoardSetTimelineEvents(BoardSet boardSet) {
    for (final event in boardSet.switchEvents) {
      _processedTimelineEvents.add(
        _timelineEventKey(
          LiveAudioProbeMessage(
            kind: LiveAudioProbeMessageKind.boardSwitch,
            boardId: event.boardId,
            timestampSec: event.globalTimestampSec,
          ),
        ),
      );
    }
    for (final event in boardSet.viewportEvents) {
      _processedTimelineEvents.add(
        _timelineEventKey(
          LiveAudioProbeMessage(
            kind: LiveAudioProbeMessageKind.viewport,
            boardId: event.boardId,
            timestampSec: event.globalTimestampSec,
            interactionId: event.interactionId,
            viewport: event.viewport,
          ),
        ),
      );
    }
  }

  void _sendWhiteboardMessage(LiveAudioProbeMessage message) {
    final rtc = _rtc;
    if (rtc == null) {
      return;
    }
    unawaited(rtc.sendWhiteboardMessage(message).catchError(_showError));
    if (message.kind == LiveAudioProbeMessageKind.boardCreate ||
        message.kind == LiveAudioProbeMessageKind.boardSwitch ||
        message.kind == LiveAudioProbeMessageKind.viewport) {
      _processedTimelineEvents.add(_timelineEventKey(message));
      _pendingTimelineMessages.add(message);
    }
  }

  void _announceCurrentBoardState() {
    final boardId = _boardState.selectedBoardId;
    final timestamp = _currentTimelineSec;
    final switchMessage = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardSwitch,
      boardId: boardId,
      timestampSec: timestamp,
    );
    final viewportMessage = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.viewport,
      boardId: boardId,
      timestampSec: timestamp,
      viewport: _boardState.boardSet.resolveViewportAt(
        boardId: boardId,
        globalTimestampSec: timestamp,
      ),
      interactionId: ++_viewportInteractionId,
    );
    setState(() {
      _boardState = _boardState
          .applyMessage(switchMessage)
          .applyMessage(viewportMessage);
    });
    _sendWhiteboardMessage(switchMessage);
    _sendWhiteboardMessage(viewportMessage);
    _scheduleSnapshotSave();
  }

  Future<void> _flushTimelineMessages() async {
    final sessionId = _sessionId;
    if (sessionId == null || _pendingTimelineMessages.isEmpty) {
      return;
    }
    final messages = List<LiveAudioProbeMessage>.from(_pendingTimelineMessages);
    _pendingTimelineMessages.removeRange(0, messages.length);
    final firstSequence = _timelineSequence;
    _timelineSequence += messages.length;
    try {
      await _service.saveTimelineChunk(
        sessionId: sessionId,
        firstSequence: firstSequence,
        messages: messages,
      );
    } catch (error) {
      _pendingTimelineMessages.insertAll(0, messages);
      _timelineSequence = firstSequence;
      _showError(error);
    }
  }

  void _scheduleSnapshotSave() {
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = Timer(const Duration(seconds: 2), () {
      final sessionId = _sessionId;
      if (sessionId == null) {
        return;
      }
      try {
        validateBoardSetForPersistence(_boardState.boardSet);
      } catch (error) {
        _showError(error);
        return;
      }
      unawaited(
        _service
            .saveBoardSnapshot(
              sessionId: sessionId,
              boardSet: _boardState.boardSet,
            )
            .catchError(_showError),
      );
    });
  }

  void _addBoard() {
    if (!_canPublish || !_boardState.boardSet.canAddBoard) {
      return;
    }
    final boardId = LessonWhiteboardBoard.generateId();
    final order = _boardState.boardSet.boards.length;
    final timestamp = _currentTimelineSec;
    final createMessage = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardCreate,
      boardId: boardId,
      boardOrder: order,
      boardTitle: 'ボード${order + 1}',
      timestampSec: timestamp,
    );
    final switchMessage = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardSwitch,
      boardId: boardId,
      timestampSec: timestamp,
    );
    setState(() {
      _boardState = _boardState
          .applyMessage(createMessage)
          .applyMessage(switchMessage);
    });
    _sendWhiteboardMessage(createMessage);
    _sendWhiteboardMessage(switchMessage);
    _scheduleSnapshotSave();
  }

  void _selectBoard(String boardId) {
    if (_canPublish) {
      final message = LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.boardSwitch,
        boardId: boardId,
        timestampSec: _currentTimelineSec,
      );
      setState(() => _boardState = _boardState.applyMessage(message));
      _sendWhiteboardMessage(message);
      _scheduleSnapshotSave();
      return;
    }
    if (!_followPresenter) {
      setState(() {
        _viewerBoardId = boardId;
        _viewerViewport = _boardState.boardSet.resolveViewportAt(
          boardId: boardId,
          globalTimestampSec: _isCatchup
              ? _catchupTimelineSec
              : double.infinity,
        );
      });
    }
  }

  void _handleViewportChanged(LessonWhiteboardViewportChange change) {
    if (!_canPublish) {
      if (_followPresenter) {
        setState(() => _followPresenter = false);
      }
      setState(() => _viewerViewport = change.viewport);
      return;
    }
    if (change.phase == LessonWhiteboardViewportChangePhase.start) {
      _viewportInteractionId++;
      _lastViewportSentAt = null;
    }
    final now = DateTime.now();
    final shouldSend =
        change.phase != LessonWhiteboardViewportChangePhase.update ||
        _lastViewportSentAt == null ||
        now.difference(_lastViewportSentAt!) >=
            const Duration(milliseconds: 100);
    if (!shouldSend) {
      return;
    }
    _lastViewportSentAt = now;
    final message = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.viewport,
      boardId: _boardState.selectedBoardId,
      timestampSec: _currentTimelineSec,
      viewport: change.viewport,
      interactionId: _viewportInteractionId,
    );
    setState(() => _boardState = _boardState.applyMessage(message));
    _sendWhiteboardMessage(message);
    _scheduleSnapshotSave();
  }

  Future<void> _startCatchup(double positionSec) async {
    final session = _session;
    final rtc = _rtc;
    final hlsUrl = _participantHlsManifestUrl.isNotEmpty
        ? _participantHlsManifestUrl
        : session?.hlsManifestUrl ?? '';
    if (session == null || rtc == null || hlsUrl.isEmpty) {
      setState(() => _message = '追っかけ再生用の音声はまだ準備中です。');
      return;
    }
    try {
      await rtc.setLiveAudioMuted(true);
      await _catchup.playFrom(hlsUrl: hlsUrl, positionSec: positionSec);
    } catch (error) {
      await rtc.setLiveAudioMuted(false);
      _showError(error);
    }
  }

  Future<void> _returnToLive() async {
    await _catchup.returnToLive();
    await _rtc?.setLiveAudioMuted(false);
    if (mounted) {
      setState(() {
        _followPresenter = true;
        _viewerBoardId = null;
        _viewerViewport = null;
        _catchupSeekSec = null;
      });
    }
  }

  Future<void> _copySessionCode() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: sessionId));
    if (mounted) {
      setState(() => _message = '配信コードをコピーしました。');
    }
  }

  Future<void> _closeSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    var closed = false;
    await _runBusy(() async {
      _timelineFlushTimer?.cancel();
      _timelineFlushTimer = null;
      _snapshotSaveTimer?.cancel();
      _snapshotSaveTimer = null;
      try {
        await _flushTimelineMessages();
        await _service.saveBoardSnapshot(
          sessionId: sessionId,
          boardSet: _boardState.boardSet,
        );
      } catch (error) {
        _showError(error);
      }
      await _service.closeSession(sessionId);
      closed = true;
      await _leaveRtcOnly();
    });
    if (closed && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _leaveRtcOnly() async {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _clock.stop();
    _timelineFlushTimer?.cancel();
    _timelineFlushTimer = null;
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = null;
    _archiveRefreshTimer?.cancel();
    _archiveRefreshTimer = null;
    await _flushTimelineMessages();
    await _cancelSubscriptions();
    await _catchup.returnToLive();
    final rtc = _rtc;
    _rtc = null;
    if (rtc != null) {
      await rtc.dispose();
    }
    if (mounted) {
      setState(() {
        _session = null;
        _participants = const [];
        _permission = null;
        _rtcState = LiveAudioProbeRtcState.idle;
        _microphoneMuted = false;
        _boardState = LiveAudioBoardState.initial();
        _localStroke = null;
        _localStrokeBoardId = null;
        _viewerBoardId = null;
        _viewerViewport = null;
        _followPresenter = true;
        _catchupSeekSec = null;
        _pendingTimelineMessages.clear();
        _processedTimelineEvents.clear();
        _timelineSequence = 0;
        _participantHlsManifestUrl = '';
        _archiveAvailableDurationSec = 0;
      });
    }
    _leaving = false;
  }

  Future<void> _cancelSubscriptions() async {
    await _statusSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _sessionSubscription?.cancel();
    await _participantsSubscription?.cancel();
    await _savedStrokesSubscription?.cancel();
    await _timelineSubscription?.cancel();
    _statusSubscription = null;
    _messageSubscription = null;
    _sessionSubscription = null;
    _participantsSubscription = null;
    _savedStrokesSubscription = null;
    _timelineSubscription = null;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    final message = switch (error) {
      FirebaseFunctionsException(:final message?) => message,
      FirebaseException(:final message?) => message,
      _ => error.toString(),
    };
    setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ライブ音声・板書配信')),
      body: SafeArea(child: _session == null ? _buildLobby() : _buildRoom()),
    );
  }

  Widget _buildLobby() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('ライブ音声、複数ボード、ズーム操作を共有します。配信音声は自動的にアーカイブされます。'),
          ),
        ),
        const SizedBox(height: 16),
        if (_isTeacher) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _createAndJoin,
            icon: const Icon(Icons.podcasts),
            label: const Text('先生として配信を開始'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(),
          ),
        ],
        TextField(
          controller: _sessionCodeController,
          enabled: !_busy,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: '配信コード',
            hintText: '先生から届いた20文字のコード',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _joinEnteredSession,
          icon: const Icon(Icons.login),
          label: const Text('この配信へ参加'),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_message != null) _MessageCard(message: _message!),
      ],
    );
  }

  Widget _buildRoom() {
    final board = _displayBoard;
    final completedStrokes = _isCatchup
        ? visibleWhiteboardBundleStrokes(
            bundle: board.layerBundle,
            globalPositionSec: _catchupTimelineSec,
            segmentLocalPositionSec: _catchupStatus.positionSec,
          )
        : board.layerBundle.primaryLayer?.strokes ?? const <WhiteboardStroke>[];
    final displayStrokes = <WhiteboardStroke>[
      ...completedStrokes,
      if (!_isCatchup) ..._boardState.remoteInProgressStrokesForBoard(board.id),
    ];
    final session = _session!;
    final catchupManifestUrl = _participantHlsManifestUrl.isNotEmpty
        ? _participantHlsManifestUrl
        : session.hlsManifestUrl;
    final serverAvailableSec =
        _archiveAvailableDurationSec > session.hlsAvailableDurationSec
        ? _archiveAvailableDurationSec
        : session.hlsAvailableDurationSec;
    final availableCatchupSec = serverAvailableSec > 0
        ? serverAvailableSec
        : (_currentSessionSec - 20).clamp(0, double.infinity).toDouble();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '配信コード: ${session.id}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: _copySessionCode,
              icon: const Icon(Icons.copy),
              tooltip: '配信コードをコピー',
            ),
          ],
        ),
        Text('接続状態: ${_rtcStateLabel(_rtcState)}'),
        Text('現在の権限: ${_canPublish ? '発表者' : '視聴専用'}'),
        Text('アーカイブ: ${_archiveStatusLabel(session.archiveStatus)}'),
        if (_message != null) _MessageCard(message: _message!),
        if (_isOwner && session.archiveFailed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _runBusy(() => _service.retryArchive(session.id)),
              icon: const Icon(Icons.refresh),
              label: const Text('アーカイブ録音を再試行'),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final item in _boardState.boardSet.orderedBoards)
              ChoiceChip(
                label: Text(
                  item.title.isEmpty ? 'ボード${item.order + 1}' : item.title,
                ),
                selected: item.id == board.id,
                onSelected: (_) => _selectBoard(item.id),
              ),
            if (_canPublish && _boardState.boardSet.canAddBoard)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('ボード追加'),
                onPressed: _addBoard,
              ),
          ],
        ),
        if (!_canPublish && !_isCatchup)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('発表者のボードと表示範囲を追従'),
            value: _followPresenter,
            onChanged: (value) {
              setState(() {
                _followPresenter = value;
                if (value) {
                  _viewerBoardId = null;
                  _viewerViewport = null;
                }
              });
            },
          ),
        if (!_canPublish && availableCatchupSec > 0) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCatchup
                        ? '追っかけ再生中: ${_formatSeconds(_catchupStatus.positionSec)}'
                        : '追っかけ再生可能: 0:00〜${_formatSeconds(availableCatchupSec)}',
                  ),
                  Slider(
                    min: 0,
                    max: availableCatchupSec <= 0 ? 1 : availableCatchupSec,
                    value:
                        (_isCatchup
                                ? (_catchupSeekSec ??
                                      _catchupStatus.positionSec)
                                : (_catchupSeekSec ?? availableCatchupSec))
                            .clamp(
                              0,
                              availableCatchupSec <= 0
                                  ? 1
                                  : availableCatchupSec,
                            )
                            .toDouble(),
                    onChanged: catchupManifestUrl.isEmpty
                        ? null
                        : (value) => setState(() => _catchupSeekSec = value),
                    onChangeEnd: catchupManifestUrl.isEmpty
                        ? null
                        : (value) => unawaited(_startCatchup(value)),
                  ),
                  if (_isCatchup)
                    FilledButton.icon(
                      onPressed: _returnToLive,
                      icon: const Icon(Icons.sensors),
                      label: const Text('ライブに戻る'),
                    )
                  else if (catchupManifestUrl.isEmpty)
                    const Text('音声断片を準備しています。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        LessonWhiteboardCanvas(
          strokes: displayStrokes,
          inProgressStroke: !_isCatchup && _localStrokeBoardId == board.id
              ? _localStroke
              : null,
          drawingEnabled: _canPublish && _isConnected && !_isCatchup,
          onStrokeStart: _startLocalStroke,
          onStrokeUpdate: _updateLocalStroke,
          onStrokeEnd: _endLocalStroke,
          onStrokeCancel: () => setState(_cancelLocalStroke),
          viewport: _displayViewport,
          onViewportChanged: _isCatchup ? null : _handleViewportChanged,
          viewportInteractionEnabled: !_isCatchup,
          showViewportControls: !_isCatchup,
        ),
        const SizedBox(height: 12),
        if (_canPublish)
          FilledButton.icon(
            onPressed: _isConnected ? _toggleMicrophone : null,
            icon: Icon(_microphoneMuted ? Icons.mic_off : Icons.mic),
            label: Text(_microphoneMuted ? 'マイクをオンにする' : 'マイクをミュート'),
          ),
        if (_isOwner) ...[
          const SizedBox(height: 20),
          const Text(
            '参加者と発表許可',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final participant in _participants)
            SwitchListTile(
              title: Text(participant.displayName),
              subtitle: Text(
                session.activePresenterUid == participant.uid
                    ? '現在の発表者（音声・板書・画面操作）'
                    : '視聴専用',
              ),
              value: session.activePresenterUid == participant.uid,
              onChanged:
                  _presenterUpdates.contains(participant.uid) ||
                      (participant.uid == session.ownerUid &&
                          session.activePresenterUid == session.ownerUid)
                  ? null
                  : (enabled) => _togglePresenter(participant, enabled),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _closeSession,
            icon: const Icon(Icons.stop_circle),
            label: const Text('配信を終了して下書きを作成'),
          ),
        ] else ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _leaveRtcOnly,
            child: const Text('退出する'),
          ),
        ],
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
      ),
    );
  }
}

String _rtcStateLabel(LiveAudioProbeRtcState state) {
  return switch (state) {
    LiveAudioProbeRtcState.idle => '未接続',
    LiveAudioProbeRtcState.connecting => '接続中',
    LiveAudioProbeRtcState.connected => '接続済み',
    LiveAudioProbeRtcState.reconnecting => '再接続中',
    LiveAudioProbeRtcState.disconnected => '切断',
    LiveAudioProbeRtcState.failed => 'エラー',
  };
}

String _archiveStatusLabel(String status) {
  return switch (status) {
    'starting' => '録音を開始しています',
    'recording' => '配信と同時に保存中',
    'available' => '追っかけ再生を利用できます',
    'stopping' => '録音を停止しています',
    'finalizing' => '音声を確定中',
    'draftReady' => '先生用下書きの準備完了',
    'failed' => '録音に問題があります（ライブは継続）',
    'archiveFailed' => '録音に問題があります（ライブは継続）',
    _ => '設定を確認中',
  };
}

String _formatSeconds(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final minutes = total ~/ 60;
  final remainder = total % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

String _timelineEventKey(LiveAudioProbeMessage message) {
  final viewport = message.viewport;
  return '${message.kind.name}|${message.boardId}|'
      '${message.timestampSec.toStringAsFixed(5)}|'
      '${message.boardOrder ?? ''}|${message.boardTitle ?? ''}|'
      '${message.interactionId ?? ''}|'
      '${viewport?.centerX ?? ''}|${viewport?.centerY ?? ''}|'
      '${viewport?.scale ?? ''}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
