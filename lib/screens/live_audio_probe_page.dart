import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../models/lesson_payload_size_validator.dart';
import '../services/live_audio_board_selection.dart';
import '../services/live_audio_board_state.dart';
import '../services/live_audio_catchup_playback.dart';
import '../services/live_audio_microphone_permission.dart';
import '../services/live_audio_permission_apply.dart';
import '../services/live_audio_probe_message.dart';
import '../services/live_audio_probe_rtc.dart';
import '../services/live_audio_probe_service.dart';
import '../services/live_audio_rtc_initialization_guard.dart';
import '../services/live_audio_snapshot_tracker.dart';
import '../services/live_audio_stroke_persistence.dart';
import '../services/live_audio_timeline_clock.dart';
import '../services/live_audio_timeline_outbox.dart';
import '../services/lesson_material_cache_service.dart';
import '../widgets/async_route_exit_scope.dart';
import '../widgets/lesson_whiteboard_canvas.dart';

const bool liveAudioProbeEnabled = bool.fromEnvironment(
  'ENABLE_LIVE_AUDIO',
  defaultValue: bool.fromEnvironment('ENABLE_AGORA_PROBE', defaultValue: true),
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
  int? _timelineClockAnchorMs;
  int? _timelineClockAnchorElapsedUs;
  Future<bool>? _timelineClockSyncOperation;
  bool _timelineClockConfirmed = false;
  bool _timelineClockSyncing = false;
  bool _currentBoardStateAnnounced = false;
  final Set<String> _presenterUpdates = {};
  final Set<String> _processedTimelineEvents = {};
  final Set<String> _timelineCreatedBoardIds = {};
  final Set<String> _serverBoardIds = {};
  final LiveAudioTimelineOutbox _timelineOutbox = LiveAudioTimelineOutbox();
  final LiveAudioSnapshotTracker _snapshotTracker = LiveAudioSnapshotTracker();
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
  bool? _localDrawer;
  int _viewportInteractionId = 0;
  DateTime? _lastViewportSentAt;
  Timer? _timelineFlushTimer;
  Timer? _snapshotSaveTimer;
  Timer? _archiveRefreshTimer;
  Timer? _durationLimitTimer;
  Future<void>? _snapshotSaveFuture;
  Future<void>? _returnToLiveOperation;
  LiveAudioCatchupStatus _catchupStatus = const LiveAudioCatchupStatus(
    state: LiveAudioCatchupState.live,
  );
  double? _catchupSeekSec;
  bool _busy = false;
  bool _microphoneMuted = false;
  bool _applyingPermission = false;
  int _permissionApplyFollowUps = 0;
  bool _closingSession = false;
  String? _message;
  String _participantHlsManifestUrl = '';
  double _archiveAvailableDurationSec = 0;
  double? _archiveMediaTimelineOffsetSec;
  double? _archiveAudioPlaybackCompensationSec;
  bool _suspendLiveRtcMessages = false;
  final LessonMaterialCacheService _materialCache =
      LessonMaterialCacheService();
  LessonMaterialCacheStatus? _materialCacheStatus;
  LessonMaterialDownloadProgress? _materialDownloadProgress;
  bool _materialDownloadBusy = false;
  bool _cancelMaterialDownload = false;
  bool _materialServerValidated = false;
  String? _lastMaterialFingerprint;
  Future<void>? _leaveRtcOperation;
  Future<void>? _routeCleanupOperation;
  Future<void>? _serverCloseOperation;

  bool get _isTeacher => widget.activeRole == 'teacher';
  bool get _isOwner => _session?.ownerUid == widget.user.uid;
  bool get _isConnected =>
      _rtcState == LiveAudioProbeRtcState.connected ||
      _rtcState == LiveAudioProbeRtcState.reconnecting;
  bool get _canPublish => _permission?.canPublish == true && !_closingSession;
  bool get _isDrawer {
    final session = _session;
    if (session != null) {
      return session.isDrawer(widget.user.uid);
    }
    return _localDrawer == true;
  }

  // This is intentionally the single gate for every teacher action written to
  // the shared timeline: strokes, viewport zoom/pan, board/PDF page switching,
  // board creation, and the initial board announcement. Do not narrow it to
  // drawing alone. Viewer-only board and viewport changes stay local and must
  // remain available without an NTP-confirmed publishing clock.
  bool get _canUseSharedTimeline => canEmitLiveAudioTimelineEvents(
    canPublish: _isDrawer && !_closingSession,
    sessionIsActive: _session?.isActive == true,
    ntpClockConfirmed: _timelineClockConfirmed,
  );
  bool get _canWriteBoard => _canUseSharedTimeline;
  String? get _sessionId => _session?.id;
  bool get _isCatchup =>
      _catchupStatus.state == LiveAudioCatchupState.catchup ||
      _catchupStatus.state == LiveAudioCatchupState.loading;
  Set<String> get _boardsCreatedDuringSession => {
    ...?_session?.timelineCreatedBoardIds,
    ..._timelineCreatedBoardIds,
  };
  String get _displayBoardId => resolveLiveAudioDisplayBoardId(
    boardSet: _boardState.boardSet,
    presenterBoardId: _boardState.selectedBoardId,
    isCatchup: _isCatchup,
    followPresenter: _isDrawer || _followPresenter,
    viewerBoardId: _viewerBoardId,
    catchupTimelineSec: _catchupTimelineSec,
    boardsCreatedDuringSession: _boardsCreatedDuringSession,
  );

  List<LessonWhiteboardBoard> get _selectableBoards => _isCatchup
      ? liveAudioBoardsAvailableAt(
          boardSet: _boardState.boardSet,
          globalTimestampSec: _catchupTimelineSec,
          boardsCreatedDuringSession: _boardsCreatedDuringSession,
        )
      : _boardState.boardSet.orderedBoards;

  LessonWhiteboardBoard get _displayBoard =>
      _boardState.boardSet.boardById(_displayBoardId) ??
      _boardState.selectedBoard;
  LessonWhiteboardViewport get _displayViewport {
    if (!_isDrawer && !_followPresenter && _viewerViewport != null) {
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
        if (status.state == LiveAudioCatchupState.loading ||
            status.state == LiveAudioCatchupState.catchup) {
          final retainedViewerBoardId = retainLiveAudioViewerBoardAt(
            boardSet: _boardState.boardSet,
            viewerBoardId: _viewerBoardId,
            globalTimestampSec: _catchupTimelineSecForPosition(
              status.positionSec,
            ),
            boardsCreatedDuringSession: _boardsCreatedDuringSession,
          );
          if (retainedViewerBoardId != _viewerBoardId) {
            _viewerBoardId = retainedViewerBoardId;
            _viewerViewport = null;
          }
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
    unawaited(_cleanupRouteResources());
    super.dispose();
  }

  Future<void> _cleanupRouteResources() {
    final existing = _routeCleanupOperation;
    if (existing != null) {
      return existing;
    }
    final operation = () async {
      try {
        await _serverCloseOperation;
      } catch (error, stackTrace) {
        debugPrint(
          'Failed to wait for live session close: $error\n$stackTrace',
        );
      }
      try {
        await _leaveRtcOnly(updateUi: false);
      } catch (error, stackTrace) {
        debugPrint('Failed to close live RTC resources: $error\n$stackTrace');
      }
      final catchupSubscription = _catchupSubscription;
      _catchupSubscription = null;
      try {
        await catchupSubscription?.cancel();
      } catch (error, stackTrace) {
        debugPrint(
          'Failed to cancel catch-up subscription: $error\n$stackTrace',
        );
      }
      try {
        await _catchup.dispose();
      } catch (error, stackTrace) {
        debugPrint('Failed to close catch-up playback: $error\n$stackTrace');
      }
    }();
    _routeCleanupOperation = operation;
    return operation;
  }

  Future<void> _createAndJoin() async {
    await _runBusy(() async {
      await ensureLiveAudioMicrophonePermission();
      final createdSession = await _service.createSession(
        courseId: widget.courseId,
        lessonId: widget.lessonId,
        segmentId: widget.segmentId,
        initialBoardSet: _boardState.boardSet,
        segmentStartSec: widget.segmentStartSec,
      );
      final sessionId = createdSession.sessionId;
      _sessionCodeController.text = createdSession.joinCode;
      widget.onSessionCreated?.call(sessionId);
      try {
        await _connect(sessionId);
      } on LiveAudioRtcInitializationException {
        try {
          await _service.closeSession(sessionId);
        } catch (error) {
          debugPrint(
            '[LiveAudioRtc] failed to close session after initialization '
            'timeout: $error',
          );
        }
        rethrow;
      }
    });
  }

  Future<void> _joinEnteredSession() async {
    final joinCode = _sessionCodeController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(joinCode)) {
      setState(() => _message = '4桁の配信コードを入力してください。');
      return;
    }
    await _runBusy(() async {
      final sessionId = await _service.resolveJoinCode(joinCode);
      await _connect(sessionId);
    });
  }

  Future<void> _connect(String sessionId) async {
    await _leaveRtcOnly();
    final credentials = await _service.issueToken(sessionId);
    if (!mounted) {
      return;
    }
    _permission = credentials.permission;
    _localDrawer = credentials.canDraw;
    _participantHlsManifestUrl = credentials.hlsManifestUrl;
    final rtc = LiveAudioProbeRtcController(
      refreshToken: () => _service.issueToken(sessionId),
      onCredentialsApplied: _syncPermissionFromRtcCredentials,
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
    _messageSubscription = rtc.messages.listen((message) {
      if (_suspendLiveRtcMessages) {
        return;
      }
      _applyRemoteMessage(message);
    });
    _sessionSubscription = _service.watchSession(sessionId).listen((session) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _materialServerValidated = true;
        _serverBoardIds.addAll(
          session.boardSet.boards.map((board) => board.id),
        );
        _timelineOutbox.observeServerSequence(session.timelineNextSequence);
        final shouldApplyBoardSet = _snapshotTracker.shouldApplyServerSnapshot(
          revision: session.boardSetRevision,
          preserveUnsavedLocalChanges: _isDrawer,
        );
        _snapshotTracker.observeServerRevision(session.boardSetRevision);
        if (session.boardSet.isNotEmpty && shouldApplyBoardSet) {
          _rememberBoardSetTimelineEvents(session.boardSet);
          _boardState = _boardState.replaceSnapshot(
            session.boardSet,
            preserveSelectedBoard: _isDrawer,
          );
          _snapshotTracker.markServerSnapshotApplied(session.boardSetRevision);
        }
        if (session.archiveError.isNotEmpty) {
          _message = session.archiveError;
        }
      });
      unawaited(_refreshLiveMaterialCacheStatus());
      _scheduleDurationLimit(session);
      unawaited(_applyDrawerState(session));
      _announceCurrentBoardStateIfReady();
      if (!session.isActive) {
        setState(
          () => _message = session.closeReason == 'maxDuration'
              ? '配信時間が1時間に達したため、自動的に終了しました。'
              : session.isFinalizing
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
      if (own != null && own.permission != _permission) {
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
    if (credentials.serverNowMs > 0) {
      _timelineClockAnchorMs = credentials.serverNowMs;
      _timelineClockAnchorElapsedUs = _clock.elapsedMicroseconds;
    }
    _timelineFlushTimer?.cancel();
    _timelineFlushTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_flushTimelineMessages().then<void>((_) {})),
    );
    try {
      await rtc.join(credentials);
      if (credentials.permission.canPublish) {
        unawaited(_reportAudioCaptureStart(sessionId, rtc));
      }
      await _synchronizeTimelineClock(sessionId, rtc);
    } catch (error) {
      final wasCurrentConnection = _rtc == rtc;
      if (wasCurrentConnection) {
        await _leaveRtcOnly();
      } else {
        await rtc.dispose();
      }
      if (mounted && wasCurrentConnection && !_closingSession) {
        setState(() => _rtcState = LiveAudioProbeRtcState.failed);
      }
      rethrow;
    }
    if (!mounted || _rtc != rtc || _sessionId != sessionId) {
      return;
    }
    _archiveRefreshTimer?.cancel();
    _archiveRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_refreshArchiveStatus(sessionId)),
    );
    unawaited(_refreshArchiveStatus(sessionId));
    final session = _session;
    if (session != null) {
      await _applyDrawerState(session);
    }
    _announceCurrentBoardStateIfReady();
  }

  void _scheduleDurationLimit(LiveAudioProbeSession session) {
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
    if (!session.isActive ||
        session.ownerUid != widget.user.uid ||
        session.maximumEndsAtMs <= 0) {
      return;
    }
    final remaining = Duration(
      milliseconds:
          session.maximumEndsAtMs - DateTime.now().millisecondsSinceEpoch,
    );
    if (remaining <= Duration.zero) {
      unawaited(_closeSession(automaticDurationLimit: true));
      return;
    }
    _durationLimitTimer = Timer(remaining, () {
      unawaited(_closeSession(automaticDurationLimit: true));
    });
  }

  LiveAudioProbePermission? get _ownRemotePermission {
    for (final participant in _participants) {
      if (participant.uid == widget.user.uid) {
        return participant.permission;
      }
    }
    return null;
  }

  void _syncPermissionFromRtcCredentials(
    LiveAudioProbeCredentials credentials,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _permission = credentials.permission;
      if (credentials.hlsManifestUrl.isNotEmpty) {
        _participantHlsManifestUrl = credentials.hlsManifestUrl;
      }
    });
    final sessionId = _sessionId;
    if (sessionId != null &&
        shouldFollowUpLiveAudioPermissionApply(
          localPermission: credentials.permission,
          remotePermission: _ownRemotePermission,
          followUpCount: 0,
        )) {
      unawaited(_applyPermissionChange(sessionId));
    }
  }

  Future<void> _applyPermissionChange(
    String sessionId, {
    bool isFollowUp = false,
  }) async {
    final rtc = _rtc;
    if (rtc == null || _applyingPermission) {
      return;
    }
    if (!isFollowUp) {
      _permissionApplyFollowUps = 0;
    }
    _applyingPermission = true;
    try {
      final credentials = await rtc.applyFetchedCredentials(
        () => _service.issueToken(sessionId),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _permission = credentials.permission;
        _participantHlsManifestUrl = credentials.hlsManifestUrl;
        _microphoneMuted = false;
        _currentBoardStateAnnounced = false;
        _message = credentials.permission.canPublish
            ? '一緒に話すことを許可されました。'
            : '一緒に話すことを終了し、視聴専用へ戻りました。';
      });
      if (credentials.permission.canPublish) {
        unawaited(_reportAudioCaptureStart(sessionId, rtc));
        await _synchronizeTimelineClock(sessionId, rtc);
      }
      final session = _session;
      if (session != null) {
        await _applyDrawerState(session);
      }
    } catch (error) {
      _showError(error);
    } finally {
      _applyingPermission = false;
    }
    if (!mounted) {
      return;
    }
    if (shouldFollowUpLiveAudioPermissionApply(
      localPermission: _permission,
      remotePermission: _ownRemotePermission,
      followUpCount: _permissionApplyFollowUps,
    )) {
      _permissionApplyFollowUps += 1;
      unawaited(_applyPermissionChange(sessionId, isFollowUp: true));
    } else {
      _permissionApplyFollowUps = 0;
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
        if (status.hlsMediaTimelineOffsetSec != null) {
          _archiveMediaTimelineOffsetSec = status.hlsMediaTimelineOffsetSec;
        }
        _archiveAudioPlaybackCompensationSec =
            status.audioPlaybackCompensationSec;
        if (status.archiveError.isNotEmpty) {
          _message = status.archiveError;
        }
      });
    } catch (_) {
      // 録音の準備中や一時的なquery失敗ではライブ配信を止めない。
    }
  }

  Future<void> _applyDrawerState(LiveAudioProbeSession session) async {
    final isDrawer = session.isDrawer(widget.user.uid);
    final rtc = _rtc;
    if (rtc == null ||
        (_rtcState != LiveAudioProbeRtcState.connected &&
            _rtcState != LiveAudioProbeRtcState.reconnecting)) {
      return;
    }
    if (isDrawer && !_canPublish) {
      return;
    }
    await rtc.setBoardSendingEnabled(isDrawer);
    if (_localDrawer == isDrawer) {
      return;
    }
    if (isDrawer) {
      if (!mounted) {
        _localDrawer = true;
        return;
      }
      setState(() {
        _localDrawer = true;
        _currentBoardStateAnnounced = false;
        _message = '書き物を担当します。同期後に共有操作を利用できます。';
      });
      await _synchronizeTimelineClock(session.id, rtc);
      _announceCurrentBoardStateIfReady();
      return;
    }
    if (!mounted) {
      _localDrawer = false;
      return;
    }
    setState(() {
      _localDrawer = false;
      _followPresenter = true;
      _snapshotSaveTimer?.cancel();
      _snapshotSaveTimer = null;
      _cancelLocalStroke();
      if (session.boardSet.isNotEmpty) {
        _snapshotTracker.reset(serverRevision: session.boardSetRevision);
        _rememberBoardSetTimelineEvents(session.boardSet);
        _boardState = _boardState.replaceSnapshot(
          session.boardSet,
          preserveSelectedBoard: false,
        );
        _snapshotTracker.markServerSnapshotApplied(session.boardSetRevision);
      }
      _message = '書き物の担当ではなくなりました。';
    });
  }

  Future<void> _toggleLiveControl({
    required LiveAudioProbeParticipant participant,
    required String control,
    required bool enabled,
  }) async {
    final sessionId = _sessionId;
    final updateKey = '${participant.uid}:$control';
    if (sessionId == null || _presenterUpdates.contains(updateKey)) {
      return;
    }
    setState(() => _presenterUpdates.add(updateKey));
    try {
      await _service.setPresenter(
        sessionId: sessionId,
        participantUid: participant.uid,
        enabled: enabled,
        control: control,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _presenterUpdates.remove(updateKey));
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

  // Never unlock shared timeline input by silently keeping the Functions clock
  // after NTP confirmation fails. Its request latency caused the intermittent
  // first-part offset documented in confirmLiveAudioNtpClock. The UI remains
  // locked and offers an explicit retry instead.
  Future<bool> _synchronizeTimelineClock(
    String sessionId,
    LiveAudioProbeRtcController rtc,
  ) {
    if (_timelineClockConfirmed) {
      return Future<bool>.value(true);
    }
    final existing = _timelineClockSyncOperation;
    if (existing != null) {
      return existing;
    }
    late final Future<bool> operation;
    operation = _synchronizeTimelineClockNow(sessionId, rtc).whenComplete(() {
      if (identical(_timelineClockSyncOperation, operation)) {
        _timelineClockSyncOperation = null;
      }
    });
    _timelineClockSyncOperation = operation;
    return operation;
  }

  Future<bool> _synchronizeTimelineClockNow(
    String sessionId,
    LiveAudioProbeRtcController rtc,
  ) async {
    final trustedAnchorMs = _timelineClockAnchorMs;
    final trustedAnchorElapsedUs = _timelineClockAnchorElapsedUs;
    if (trustedAnchorMs == null || trustedAnchorElapsedUs == null) {
      return false;
    }
    if (mounted && _rtc == rtc) {
      setState(() => _timelineClockSyncing = true);
    }
    final result = await confirmLiveAudioNtpClock(
      sampleNtpWallTimeMs: rtc.getNtpWallTimeInMs,
      currentElapsedUs: () => _clock.elapsedMicroseconds,
      trustedAnchorMs: trustedAnchorMs,
      trustedAnchorElapsedUs: trustedAnchorElapsedUs,
      isCancelled: () => !mounted || _rtc != rtc,
    );
    if (!mounted || _rtc != rtc) {
      return false;
    }
    if (result.confirmed) {
      setState(() {
        _timelineClockAnchorMs = result.anchorMs;
        _timelineClockAnchorElapsedUs = result.anchorElapsedUs;
        _timelineClockConfirmed = true;
        _timelineClockSyncing = false;
      });
      debugPrint(
        '[LiveAudioTimeline] Agora NTP confirmed for $sessionId after '
        '${result.attempts} samples (${result.rejectedSamples} rejected).',
      );
      return true;
    }
    setState(() => _timelineClockSyncing = false);
    debugPrint(
      '[LiveAudioTimeline] Agora NTP confirmation timed out for $sessionId '
      'after ${result.attempts} samples '
      '(${result.rejectedSamples} rejected).',
    );
    return false;
  }

  Future<void> _retryTimelineClockSync() async {
    final rtc = _rtc;
    final sessionId = _sessionId;
    if (rtc == null || sessionId == null || _timelineClockSyncing) {
      return;
    }
    await _synchronizeTimelineClock(sessionId, rtc);
    _announceCurrentBoardStateIfReady();
  }

  double get _currentSessionSec {
    return resolveLiveAudioSessionElapsedSec(
      sessionStartedAtMs: _session?.startedAtMs ?? 0,
      localNowMs: DateTime.now().millisecondsSinceEpoch,
      currentElapsedUs: _clock.elapsedMicroseconds,
      synchronizedAnchorMs: _timelineClockAnchorMs,
      synchronizedAnchorElapsedUs: _timelineClockAnchorElapsedUs,
    );
  }

  double get _effectiveSegmentStartSec => resolveLiveAudioSegmentStartSec(
    fallbackSegmentStartSec: widget.segmentStartSec,
    sessionSegmentStartSec: _session?.segmentStartSec,
  );

  double get _currentTimelineSec =>
      _effectiveSegmentStartSec + _currentSessionSec;

  double get _catchupTimelineSec =>
      _catchupTimelineSecForPosition(_catchupStatus.positionSec);

  // Catch-up and finalized playback must use the same HLS origin and the same
  // per-session compensation. See the matching version-gated subtraction in
  // functions/src/index.ts before changing this calculation.
  double _catchupTimelineSecForPosition(double positionSec) =>
      resolveLiveAudioCatchupTimelineSec(
        fallbackSegmentStartSec: widget.segmentStartSec,
        sessionSegmentStartSec: _session?.segmentStartSec,
        archiveTimelineOffsetSec: _session?.archiveTimelineOffsetSec ?? 0,
        hlsMediaTimelineOffsetSec:
            _archiveMediaTimelineOffsetSec ??
            _session?.hlsMediaTimelineOffsetSec,
        audioPlaybackCompensationSec:
            _archiveAudioPlaybackCompensationSec ??
            _session?.audioPlaybackCompensationSec ??
            0,
        positionSec: positionSec,
      );

  Future<void> _reportAudioCaptureStart(
    String sessionId,
    LiveAudioProbeRtcController rtc,
  ) async {
    // Report the first outgoing Android audio frame, not the time this request
    // runs. Functions compares it with the HLS audio-track origin to measure
    // this session's recording-pipeline delay. Failure is non-fatal because the
    // server has a documented fallback.
    final timestamp = await rtc.waitForAudioCaptureStartNtpTimeInMs();
    if (timestamp == null ||
        !mounted ||
        _rtc != rtc ||
        _sessionId != sessionId) {
      return;
    }
    try {
      await _service.reportAudioCaptureStart(
        sessionId: sessionId,
        audioCaptureStartedAtMs: timestamp,
      );
    } catch (error) {
      debugPrint('[LiveAudioProbe] audio capture time report failed: $error');
    }
  }

  void _startLocalStroke() {
    if (!_canWriteBoard) {
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
    if (stroke == null || !_canUseSharedTimeline) {
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
    if (stroke == null || !_canUseSharedTimeline) {
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
      final boardExistsOnServer = _serverBoardIds.contains(boardId);
      _scheduleSnapshotSave();
      unawaited(
        persistLiveAudioStrokeInOrder(
          boardExistsOnServer: boardExistsOnServer,
          saveBoardSnapshot: _saveBoardSnapshotNow,
          saveStroke: () => _service.saveStroke(
            sessionId: sessionId,
            boardId: boardId,
            stroke: completed,
          ),
        ).catchError(_showError),
      );
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
      if (message.kind == LiveAudioProbeMessageKind.boardCreate) {
        _timelineCreatedBoardIds.add(message.boardId);
      }
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
    if (!_canUseSharedTimeline) {
      return;
    }
    final rtc = _rtc;
    if (rtc != null && _isConnected) {
      unawaited(rtc.sendWhiteboardMessage(message).catchError(_showError));
    }
    if (message.kind == LiveAudioProbeMessageKind.boardCreate ||
        message.kind == LiveAudioProbeMessageKind.boardSwitch ||
        message.kind == LiveAudioProbeMessageKind.viewport) {
      _processedTimelineEvents.add(_timelineEventKey(message));
      _timelineOutbox.add(message);
    }
  }

  void _announceCurrentBoardStateIfReady() {
    if (!_canUseSharedTimeline || _currentBoardStateAnnounced) {
      return;
    }
    _currentBoardStateAnnounced = true;
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

  Future<bool> _flushTimelineMessages() async {
    final sessionId = _sessionId;
    if (sessionId == null || !_timelineOutbox.hasMessages) {
      return true;
    }
    try {
      await _timelineOutbox.flushNext(
        ({required firstSequence, required messages}) =>
            _service.saveTimelineChunk(
              sessionId: sessionId,
              firstSequence: firstSequence,
              messages: messages,
            ),
      );
      return true;
    } catch (error) {
      if (error case FirebaseFunctionsException(:final code)) {
        if (code == 'invalid-argument') {
          _timelineOutbox.discardRetryBatch();
          _showError(error);
          return true;
        }
        if (code == 'aborted' || code == 'already-exists') {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          _timelineOutbox.rebaseRetryBatch(
            _session?.timelineNextSequence ?? _timelineOutbox.nextSequence,
          );
        }
      }
      _showError(error);
      return false;
    }
  }

  void _scheduleSnapshotSave() {
    _snapshotTracker.markChanged();
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_saveBoardSnapshotNow().catchError(_showError));
    });
  }

  Future<void> _saveBoardSnapshotNow() {
    final active = _snapshotSaveFuture;
    if (active != null) {
      return active;
    }
    late final Future<void> tracked;
    tracked = _saveDirtyBoardSnapshots().whenComplete(() {
      if (identical(_snapshotSaveFuture, tracked)) {
        _snapshotSaveFuture = null;
      }
    });
    _snapshotSaveFuture = tracked;
    return tracked;
  }

  Future<void> _saveDirtyBoardSnapshots() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    while (_snapshotTracker.hasUnsavedChanges) {
      final generation = _snapshotTracker.changeGeneration;
      final expectedRevision = _snapshotTracker.serverRevision;
      final boardSet = _boardState.boardSet;
      validateBoardSetForPersistence(boardSet);
      try {
        final revision = await _service.saveBoardSnapshot(
          sessionId: sessionId,
          boardSet: boardSet,
          expectedRevision: expectedRevision,
        );
        if (_sessionId == sessionId) {
          _serverBoardIds.addAll(boardSet.boards.map((board) => board.id));
        }
        _snapshotTracker.markSaved(generation: generation, revision: revision);
      } on FirebaseFunctionsException catch (error) {
        if (error.code != 'aborted') {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_snapshotTracker.serverRevision == expectedRevision) {
          rethrow;
        }
      }
    }
  }

  void _addBoard() {
    if (!_canUseSharedTimeline || !_boardState.boardSet.canAddBoard) {
      return;
    }
    final boardId = LessonWhiteboardBoard.generateId();
    final order = _boardState.boardSet.boards.fold<int>(
      0,
      (next, board) => board.order >= next ? board.order + 1 : next,
    );
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
      _timelineCreatedBoardIds.add(boardId);
      _boardState = _boardState
          .applyMessage(createMessage)
          .applyMessage(switchMessage);
    });
    _sendWhiteboardMessage(createMessage);
    _sendWhiteboardMessage(switchMessage);
    _scheduleSnapshotSave();
  }

  void _selectBoard(String boardId) {
    if (_isDrawer) {
      if (!_canUseSharedTimeline) {
        return;
      }
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
    if (_boardState.boardSet.boardById(boardId) == null ||
        (_isCatchup &&
            !liveAudioBoardExistsAt(
              boardSet: _boardState.boardSet,
              boardId: boardId,
              globalTimestampSec: _catchupTimelineSec,
              boardsCreatedDuringSession: _boardsCreatedDuringSession,
            ))) {
      return;
    }
    setState(() {
      _followPresenter = false;
      _viewerBoardId = boardId;
      _viewerViewport = _isCatchup
          ? null
          : _boardState.boardSet.resolveViewportAt(
              boardId: boardId,
              globalTimestampSec: double.infinity,
            );
    });
  }

  void _handleViewportChanged(LessonWhiteboardViewportChange change) {
    if (!_isDrawer) {
      if (_followPresenter) {
        setState(() => _followPresenter = false);
      }
      setState(() => _viewerViewport = change.viewport);
      return;
    }
    if (!_canUseSharedTimeline) {
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
    _suspendLiveRtcMessages = true;
    try {
      await rtc.setLiveAudioMuted(true);
      await _catchup.playFrom(hlsUrl: hlsUrl, positionSec: positionSec);
    } catch (error) {
      _suspendLiveRtcMessages = false;
      await rtc.setLiveAudioMuted(false);
      _showError(error);
    }
  }

  Future<void> _returnToLive() {
    return _returnToLiveOperation ??= _returnToLiveNow().whenComplete(() {
      _returnToLiveOperation = null;
    });
  }

  Future<void> _returnToLiveNow() async {
    final rtc = _rtc;
    if (rtc == null) {
      return;
    }
    final connected = await rtc.waitUntilConnected();
    if (!connected) {
      if (mounted) {
        setState(() {
          _message = 'ライブ配信へ再接続しています。接続が戻ってから、もう一度お試しください。';
        });
      }
      return;
    }
    try {
      await rtc.setLiveAudioMuted(false);
      try {
        await _catchup.returnToLive();
      } catch (_) {
        await rtc.setLiveAudioMuted(true);
        rethrow;
      }
      _suspendLiveRtcMessages = false;
      if (mounted) {
        setState(() {
          _followPresenter = true;
          _viewerBoardId = null;
          _viewerViewport = null;
          _catchupSeekSec = null;
          _message = null;
        });
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _copySessionCode() async {
    final joinCode = _session?.joinCode ?? '';
    if (!RegExp(r'^\d{4}$').hasMatch(joinCode)) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: joinCode));
    if (mounted) {
      setState(() => _message = '配信コードをコピーしました。');
    }
  }

  Future<void> _closeEnteredSessionWithoutAgora() async {
    final joinCode = _sessionCodeController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(joinCode)) {
      setState(() => _message = '終了する配信の4桁のコードを入力してください。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('この配信を終了しますか？'),
        content: const Text('Agoraへ接続できない場合の緊急終了です。終了すると、この配信へは戻れません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('配信を終了'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    var closed = false;
    await _runBusy(() async {
      final sessionId = await _service.resolveJoinCode(joinCode);
      await _service.closeSession(sessionId);
      closed = true;
    });
    if (closed && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _closeAllOwnedSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('残っている配信をすべて終了しますか？'),
        content: const Text('自分が開始したまま残っている配信だけを終了します。ほかの先生の配信には影響しません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('すべて終了'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    var closedCount = 0;
    await _runBusy(() async {
      closedCount = await _service.closeOwnedActiveSessions();
    });
    if (!mounted) {
      return;
    }
    if (closedCount == 0) {
      setState(() => _message = '終了が必要な配信はありませんでした。');
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _flushAllTimelineMessages() async {
    while (_timelineOutbox.hasMessages) {
      if (!await _flushTimelineMessages()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _closeSession({bool automaticDurationLimit = false}) async {
    final sessionId = _sessionId;
    if (sessionId == null || _closingSession) {
      return;
    }
    var closed = false;
    _closingSession = true;
    setState(() {
      _message = automaticDurationLimit ? '配信時間が1時間に達したため、自動終了しています。' : null;
    });
    _timelineFlushTimer?.cancel();
    _timelineFlushTimer = null;
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = null;
    final serverClose = () async {
      await _saveBoardSnapshotNow();
      if (!await _flushAllTimelineMessages()) {
        return false;
      }
      await _service.closeSession(sessionId);
      return true;
    }();
    _serverCloseOperation = serverClose.then<void>((_) {}, onError: (_) {});
    try {
      closed = await serverClose;
      if (!closed) {
        setState(() {
          _message = '板書の保存が完了していません。通信を確認して、もう一度終了してください。';
        });
      } else {
        await _leaveRtcOnly();
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (!closed && mounted) {
        setState(() => _closingSession = false);
        _timelineFlushTimer ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_flushTimelineMessages().then<void>((_) {})),
        );
        if (_snapshotTracker.hasUnsavedChanges) {
          _snapshotSaveTimer ??= Timer(const Duration(seconds: 2), () {
            unawaited(_saveBoardSnapshotNow().catchError(_showError));
          });
        }
      }
    }
    if (closed && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _leaveRtcOnly({bool updateUi = true}) {
    final existing = _leaveRtcOperation;
    if (existing != null) {
      return existing;
    }
    final operation = _performLeaveRtcOnly(updateUi: updateUi);
    _leaveRtcOperation = operation;
    return operation.whenComplete(() {
      if (identical(_leaveRtcOperation, operation)) {
        _leaveRtcOperation = null;
      }
    });
  }

  Future<void> _performLeaveRtcOnly({required bool updateUi}) async {
    final leavingSessionId = _sessionId;
    final shouldReleaseRoles =
        !_isOwner && leavingSessionId != null && !_closingSession;
    if (shouldReleaseRoles) {
      try {
        await _service.leaveSession(leavingSessionId);
      } catch (error, stackTrace) {
        debugPrint('Failed to release live roles: $error\n$stackTrace');
      }
    }
    _clock.stop();
    _timelineFlushTimer?.cancel();
    _timelineFlushTimer = null;
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = null;
    _archiveRefreshTimer?.cancel();
    _archiveRefreshTimer = null;
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
    _suspendLiveRtcMessages = false;
    await _flushAllTimelineMessages();
    await _cancelSubscriptions();
    await _catchup.returnToLive();
    final rtc = _rtc;
    _rtc = null;
    _timelineClockSyncOperation = null;
    if (rtc != null) {
      await rtc.dispose();
    }
    if (updateUi && mounted) {
      setState(() {
        _session = null;
        _participants = const [];
        _permission = null;
        _localDrawer = null;
        _rtcState = LiveAudioProbeRtcState.idle;
        _microphoneMuted = false;
        _boardState = LiveAudioBoardState.initial();
        _localStroke = null;
        _localStrokeBoardId = null;
        _viewerBoardId = null;
        _viewerViewport = null;
        _followPresenter = true;
        _catchupSeekSec = null;
        _timelineOutbox.clear();
        _snapshotTracker.reset();
        _processedTimelineEvents.clear();
        _timelineCreatedBoardIds.clear();
        _serverBoardIds.clear();
        _participantHlsManifestUrl = '';
        _archiveAvailableDurationSec = 0;
        _archiveMediaTimelineOffsetSec = null;
        _archiveAudioPlaybackCompensationSec = null;
        _timelineClockAnchorMs = null;
        _timelineClockAnchorElapsedUs = null;
        _timelineClockConfirmed = false;
        _timelineClockSyncing = false;
        _currentBoardStateAnnounced = false;
        _materialServerValidated = false;
        _materialCacheStatus = null;
        _lastMaterialFingerprint = null;
      });
    }
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

  Future<void> _refreshLiveMaterialCacheStatus({bool force = false}) async {
    final session = _session;
    if (!_materialCache.supported ||
        _isTeacher ||
        session == null ||
        session.courseId.isEmpty ||
        session.lessonId.isEmpty) {
      return;
    }
    final fingerprint = lessonMaterialFingerprint(_boardState.boardSet);
    if (fingerprint.isEmpty ||
        (!force &&
            fingerprint == _lastMaterialFingerprint &&
            _materialCacheStatus != null)) {
      return;
    }
    _lastMaterialFingerprint = fingerprint;
    final status = await _materialCache.status(
      courseId: session.courseId,
      lessonId: session.lessonId,
      boardSet: _boardState.boardSet,
    );
    if (mounted) {
      setState(() => _materialCacheStatus = status);
    }
  }

  Future<LessonWhiteboardMaterialSource> _resolveLiveMaterialSource(
    String storagePath,
  ) async {
    final session = _session;
    if (_materialServerValidated &&
        session != null &&
        session.courseId.isNotEmpty &&
        session.lessonId.isNotEmpty) {
      final localPath = await _materialCache.localPath(
        courseId: session.courseId,
        lessonId: session.lessonId,
        boardSet: _boardState.boardSet,
        storagePath: storagePath,
      );
      if (localPath != null) {
        return LessonWhiteboardMaterialSource.file(localPath);
      }
    }
    return resolveLessonWhiteboardMaterialUrl(storagePath);
  }

  Future<void> _downloadLiveMaterials() async {
    final session = _session;
    if (_materialDownloadBusy ||
        !_materialServerValidated ||
        session == null ||
        session.courseId.isEmpty ||
        session.lessonId.isEmpty) {
      return;
    }
    setState(() {
      _materialDownloadBusy = true;
      _cancelMaterialDownload = false;
      _materialDownloadProgress = const LessonMaterialDownloadProgress(
        downloadedBytes: 0,
        totalBytes: 0,
        completedFiles: 0,
        totalFiles: 0,
      );
    });
    try {
      await _materialCache.downloadLesson(
        courseId: session.courseId,
        lessonId: session.lessonId,
        boardSet: _boardState.boardSet,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _materialDownloadProgress = progress);
          }
        },
        isCancelled: () => _cancelMaterialDownload,
      );
      _lastMaterialFingerprint = null;
      await _refreshLiveMaterialCacheStatus(force: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配信資料を端末内に保存しました。')));
      }
    } on LessonMaterialCacheCancelled {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('資料の保存をキャンセルしました。')));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _materialDownloadBusy = false;
          _materialDownloadProgress = null;
        });
      }
    }
  }

  Future<void> _deleteLiveLessonMaterials() async {
    final session = _session;
    if (_materialDownloadBusy ||
        session == null ||
        session.courseId.isEmpty ||
        session.lessonId.isEmpty) {
      return;
    }
    await _materialCache.deleteLesson(
      courseId: session.courseId,
      lessonId: session.lessonId,
    );
    _lastMaterialFingerprint = null;
    await _refreshLiveMaterialCacheStatus(force: true);
  }

  Future<void> _deleteAllLiveMaterials() async {
    if (_materialDownloadBusy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('端末内の資料をすべて削除しますか？'),
        content: const Text('他のレッスンで保存したPDF・画像も削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('すべて削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _materialCache.deleteAll();
    _lastMaterialFingerprint = null;
    await _refreshLiveMaterialCacheStatus(force: true);
  }

  String _formatMaterialBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '$bytes B';
  }

  Widget _buildLiveMaterialCacheCard() {
    final status = _materialCacheStatus;
    final progress = _materialDownloadProgress;
    final hasCurrentCache = status?.hasCurrentCache == true;
    return Card(
      key: const ValueKey('live-material-cache-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PDF・画像の事前保存', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              !_materialServerValidated
                  ? '配信資料を確認しています。'
                  : status?.hasStaleCache == true
                  ? '資料が更新されています。再保存するまでは'
                        'ネットワークから表示します。'
                  : hasCurrentCache
                  ? '配信資料は端末内に保存済みです'
                        '（${_formatMaterialBytes(status!.totalBytes)}）。'
                  : '配信中に使うPDF・画像だけを端末内に保存できます。',
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress.fraction),
              const SizedBox(height: 4),
              Text('${progress.completedFiles} / ${progress.totalFiles}件'),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _materialDownloadBusy || !_materialServerValidated
                      ? null
                      : _downloadLiveMaterials,
                  icon: const Icon(Icons.download),
                  label: Text(
                    hasCurrentCache && status?.hasStaleCache != true
                        ? '保存し直す'
                        : '配信資料を保存',
                  ),
                ),
                if (_materialDownloadBusy)
                  OutlinedButton(
                    onPressed: () => _cancelMaterialDownload = true,
                    child: const Text('キャンセル'),
                  ),
                if (hasCurrentCache || status?.hasStaleCache == true)
                  OutlinedButton(
                    onPressed: _materialDownloadBusy
                        ? null
                        : _deleteLiveLessonMaterials,
                    child: const Text('このレッスンの保存を削除'),
                  ),
                TextButton(
                  onPressed: _materialDownloadBusy
                      ? null
                      : _deleteAllLiveMaterials,
                  child: const Text('端末内の資料をすべて削除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncRouteExitScope(
      onExit: _cleanupRouteResources,
      progressLabel: '配信との接続を終了しています…',
      busyLabel: _closingSession ? 'サーバーへ保存しています' : null,
      child: Scaffold(
        appBar: AppBar(title: const Text('ライブ音声・板書配信')),
        body: SafeArea(child: _session == null ? _buildLobby() : _buildRoom()),
      ),
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
          if (widget.initialSessionId?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _runBusy(
                      () => _connect(widget.initialSessionId!.trim()),
                    ),
              icon: const Icon(Icons.meeting_room),
              label: const Text('作成済みの配信へ戻る'),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(),
          ),
        ],
        TextField(
          controller: _sessionCodeController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: '配信コード',
            hintText: '先生から届いた4桁のコード',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _joinEnteredSession,
          icon: const Icon(Icons.login),
          label: const Text('この配信へ参加'),
        ),
        if (_isTeacher) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _closeEnteredSessionWithoutAgora,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('接続せずにこの配信を終了'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _closeAllOwnedSessions,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('自分の残っている配信をすべて終了'),
          ),
        ],
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
                '配信コード: ${session.joinCode.isEmpty ? '未発行' : session.joinCode}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: session.joinCode.isEmpty ? null : _copySessionCode,
              icon: const Icon(Icons.copy),
              tooltip: '配信コードをコピー',
            ),
          ],
        ),
        Text('接続状態: ${_rtcStateLabel(_rtcState)}'),
        Text(
          '現在の権限: ${_canPublish ? (_isDrawer ? 'マイクあり・書き物担当' : 'マイクあり') : '視聴専用'}',
        ),
        Text('アーカイブ: ${_archiveStatusLabel(session.archiveStatus)}'),
        if (_isDrawer && !_timelineClockConfirmed)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timelineClockSyncing
                        ? '配信時計を同期しています…'
                        : '配信時計を確認できませんでした。',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '同期が終わるまで、書き込み、拡大・縮小、表示移動、'
                    'ボードやPDFページの切り替えは利用できません。',
                  ),
                  if (_timelineClockSyncing) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ] else ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _retryTimelineClockSync,
                      icon: const Icon(Icons.sync),
                      label: const Text('時計同期を再試行'),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
            for (final item in _selectableBoards)
              ChoiceChip(
                label: Text(
                  item.title.isEmpty ? 'ボード${item.order + 1}' : item.title,
                ),
                selected: item.id == board.id,
                onSelected: _isDrawer && !_canUseSharedTimeline
                    ? null
                    : (_) => _selectBoard(item.id),
              ),
            if (_canUseSharedTimeline && _boardState.boardSet.canAddBoard)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('ボード追加'),
                onPressed: _addBoard,
              ),
          ],
        ),
        if (!_isDrawer)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_isCatchup ? '録画時のボード切り替えを追従' : '書き物担当者のボードと表示範囲を追従'),
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
        if (!_isTeacher &&
            _materialCache.supported &&
            (_session?.courseId.isNotEmpty ?? false) &&
            (_session?.lessonId.isNotEmpty ?? false) &&
            lessonMaterialStoragePaths(_boardState.boardSet).isNotEmpty) ...[
          _buildLiveMaterialCacheCard(),
          const SizedBox(height: 12),
        ],
        LessonWhiteboardCanvas(
          strokes: displayStrokes,
          inProgressStroke: !_isCatchup && _localStrokeBoardId == board.id
              ? _localStroke
              : null,
          drawingEnabled: _canWriteBoard && !_isCatchup,
          onStrokeStart: _startLocalStroke,
          onStrokeUpdate: _updateLocalStroke,
          onStrokeEnd: _endLocalStroke,
          onStrokeCancel: () => setState(_cancelLocalStroke),
          viewport: _displayViewport,
          onViewportChanged: _isCatchup ? null : _handleViewportChanged,
          viewportInteractionEnabled:
              !_isCatchup && (!_isDrawer || _canUseSharedTimeline),
          showViewportControls: !_isCatchup,
          background: board.background,
          aspectRatio: board.aspectRatio,
          materialUrlResolver: _resolveLiveMaterialSource,
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
            '参加者と許可',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('マイクは先生と受講者1人まで同時に使えます。書き物は常にどちらか1人です。'),
          const SizedBox(height: 8),
          for (final participant in _participants)
            ..._buildParticipantPermissionTiles(session, participant),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _closingSession ? null : () => _closeSession(),
            icon: const Icon(Icons.stop_circle),
            label: Text(_closingSession ? '配信を終了しています…' : '配信を終了して下書きを作成'),
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

  List<Widget> _buildParticipantPermissionTiles(
    LiveAudioProbeSession session,
    LiveAudioProbeParticipant participant,
  ) {
    final isOwnerParticipant = participant.uid == session.ownerUid;
    final isCoSpeaker = session.coSpeakerUid == participant.uid;
    final isDrawer = session.isDrawer(participant.uid);
    if (isOwnerParticipant) {
      return [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(participant.displayName),
          subtitle: Text(isDrawer ? '先生（常に話せます・書き物担当）' : '先生（常に話せます）'),
        ),
      ];
    }
    final coSpeakerKey = '${participant.uid}:coSpeaker';
    final drawerKey = '${participant.uid}:drawer';
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(participant.displayName),
        subtitle: Text(isCoSpeaker ? '一緒に話しています' : '視聴専用'),
        value: isCoSpeaker,
        onChanged: _closingSession || _presenterUpdates.contains(coSpeakerKey)
            ? null
            : (enabled) => _toggleLiveControl(
                participant: participant,
                control: 'coSpeaker',
                enabled: enabled,
              ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('書き物を渡す'),
        subtitle: Text(
          isDrawer
              ? 'この人が書き物を担当しています'
              : isCoSpeaker
              ? 'オフの間は先生が書けます'
              : '先に「一緒に話す」を許可してください',
        ),
        value: isDrawer,
        onChanged:
            _closingSession ||
                !isCoSpeaker ||
                _presenterUpdates.contains(drawerKey)
            ? null
            : (enabled) => _toggleLiveControl(
                participant: participant,
                control: 'drawer',
                enabled: enabled,
              ),
      ),
    ];
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
