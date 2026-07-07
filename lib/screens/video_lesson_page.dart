import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/active_learning_lock.dart';
import '../models/course.dart';
import '../models/lesson_cycle_display.dart';
import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_segment_boundary.dart';
import '../models/lesson_whiteboard.dart';
import '../models/course_privacy_consent.dart';
import '../models/quiz_answer_key.dart';
import '../models/watched_range.dart';
import '../services/course_privacy_service.dart';
import '../services/lesson_media_playback.dart';
import '../services/lesson_media_playlist_playback.dart';
import '../widgets/lesson_playback_synced_whiteboard.dart';
import 'course_entry_gate.dart';
import 'lesson_questions_page.dart';
import 'lesson_notes_page.dart';

typedef QuizAnswerSaveOverride =
    Future<void> Function({
      required LessonEvent event,
      required int selectedChoiceIndex,
      required bool isCorrect,
    });

class VideoLessonPage extends StatefulWidget {
  const VideoLessonPage({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.isTeacherPreview = false,
    this.onQuizAnswerSaveOverride,
    this.playlistPlaybackFactory,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final bool isTeacherPreview;
  final QuizAnswerSaveOverride? onQuizAnswerSaveOverride;
  final LessonMediaPlaylistPlaybackFactory? playlistPlaybackFactory;

  @override
  State<VideoLessonPage> createState() => _VideoLessonPageState();
}

class _VideoLessonPageState extends State<VideoLessonPage>
    with WidgetsBindingObserver {
  static const double _completionRate = 0.92;
  static const double _resumeSeekDriftToleranceSec = 1.0;
  static const Duration _postSeekDisplaySyncInterval =
      Duration(milliseconds: 250);
  static const int _postSeekDisplaySyncTickCount = 6;
  static const Duration _resumeWindow = Duration(hours: 24);
  static const Duration _activeLearningHeartbeatInterval = Duration(
    seconds: 15,
  );
  static const Duration _activeLearningLockStaleAfter = Duration(seconds: 45);
  static const String _learningTaskStateDocId = 'current';
  static const String _activeLearningSessionDocId = 'current';
  static final String _activeLearningDeviceId =
      'device-${DateTime.now().microsecondsSinceEpoch}';

  int _currentPositionSec = 0;
  double _currentPositionSecExact = 0;
  double? _sliderDragPositionSec;
  int _studySeconds = 0;
  int _watchSeconds = 0;
  int _cycleNumber = 1;
  int? _displayCycleNumber;
  int _cycleMaxWatchedPositionSec = 0;
  bool _isPlaying = false;
  bool _isPreparingSession = false;
  bool _sessionCompleted = false;
  bool _hasPlaybackStarted = false;
  bool _pendingCompletion = false;
  bool _isLoadingLearningState = true;
  bool _isLessonNotesOpen = false;
  bool _isLessonQuestionsOpen = false;
  Timer? _playbackTimer;
  Timer? _studyTimer;
  Timer? _activeLearningHeartbeatTimer;
  Timer? _postSeekDisplaySyncTimer;
  StreamSubscription<CourseEntryRequirement>? _entryRequirementSubscription;
  String? _sessionId;
  String? _segmentId;
  bool _hasActiveLearningLock = false;
  bool _isHandlingEntryRequirementBlock = false;
  final Map<String, int> _selectedChoices = {};
  final Map<String, bool> _answerResults = {};
  final Set<String> _answeredQuizEventIds = {};
  final List<WatchedRange> _cycleWatchedRanges = [];
  String? _message;
  int _totalDurationSec = 0;
  bool _isLoadingMedia = false;
  String? _mediaLoadError;
  bool _hasReconciledOpenPlaybackPosition = false;
  LessonMediaPlaylistController? _playlistPlayback;
  StreamSubscription<double>? _positionSubscription;
  StreamSubscription<int>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;

  Course get course => widget.course;
  CourseLesson get lesson => widget.lesson;
  int get lessonNumber => widget.lessonNumber;

  LessonMediaTimeline get _mediaTimeline => lesson.mediaTimeline;

  bool get _currentSegmentIsAudio => _playlistPlayback?.currentSegmentIsAudio ?? true;

  bool get _hasWhiteboard => !lesson.publishedWhiteboardBundle.isEmpty;

  bool get _isDraggingSlider => _sliderDragPositionSec != null;

  int get _displayedPositionSec =>
      (_sliderDragPositionSec ?? _currentPositionSec.toDouble()).round();

  bool get _isTeacherPreview => widget.isTeacherPreview;
  bool get _hasMediaSource =>
      lessonHasPlayableMedia(mediaSegments: lesson.mediaSegments);
  int get _completionThresholdSec => calculateCompletionThresholdSec(
    totalDurationSec: _totalDurationSec,
    completionRate: _completionRate,
  );
  bool get _isAtEnd => isLessonPlaybackAtEnd(
    totalDurationSec: _totalDurationSec,
    positionSecExact: _currentPositionSecExact,
  );
  bool get _hasActiveSession => _sessionId != null && !_sessionCompleted;
  String get _taskKey => '${_courseId()}-$lessonNumber-$_cycleNumber';
  int get _visibleCycleNumber => _displayCycleNumber ?? _cycleNumber;
  IconData get _playButtonIcon {
    return switch (lessonPlayButtonVisual(
      isPlaying: _isPlaying,
      isAtEnd: _isAtEnd,
    )) {
      LessonPlayButtonVisual.pause => Icons.pause,
      LessonPlayButtonVisual.replay => Icons.replay,
      LessonPlayButtonVisual.play => Icons.play_arrow,
    };
  }

  String get _playButtonLabel => lessonPlayButtonLabel(
    isPreparingSession: _isPreparingSession,
    isPlaying: _isPlaying,
    isSessionCompleted: _sessionCompleted,
    isAtEnd: _isAtEnd,
  );

  List<LessonEvent> get _dueQuizEvents {
    if (_isTeacherPreview) {
      return const [];
    }
    if (!_hasActiveSession) {
      return const [];
    }

    return course.lessonEvents
        .where((event) => event.lessonNumber == lessonNumber)
        .where((event) => event.isQuiz)
        .where(
          (event) =>
              event.resolveGlobalTimestampSec(_mediaTimeline) <= _currentPositionSec,
        )
        .toList()
      ..sort(
        (a, b) => a
            .resolveGlobalTimestampSec(_mediaTimeline)
            .compareTo(b.resolveGlobalTimestampSec(_mediaTimeline)),
      );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isLoadingLearningState = Firebase.apps.isNotEmpty && !_isTeacherPreview;
    _listenEntryRequirement();
    if (_hasMediaSource) {
      _isLoadingMedia = true;
      unawaited(_initializeMediaPlayer());
    }
    if (_isLoadingLearningState) {
      unawaited(_resumeLearningTimeOnOpen());
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _studyTimer?.cancel();
    _activeLearningHeartbeatTimer?.cancel();
    _postSeekDisplaySyncTimer?.cancel();
    _entryRequirementSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    unawaited(_playlistPlayback?.close());
    WidgetsBinding.instance.removeObserver(this);
    if (!_isTeacherPreview) {
      if (_pendingCompletion && !_sessionCompleted) {
        unawaited(_completeCurrentSegment(updateUi: false));
      } else {
        unawaited(_persistSessionProgress());
      }
      unawaited(_releaseActiveLearningLock());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _studyTimer?.cancel();
      _activeLearningHeartbeatTimer?.cancel();
      if (_isTeacherPreview) {
        return;
      }
      if (_pendingCompletion && !_sessionCompleted) {
        unawaited(_completeCurrentSegment());
      } else {
        unawaited(_persistSessionProgress());
      }
      unawaited(_releaseActiveLearningLock());
      return;
    }

    if (!_isTeacherPreview &&
        state == AppLifecycleState.resumed &&
        _hasActiveSession) {
      unawaited(_resumeActiveLearningAfterLifecycle());
    }
  }

  Future<void> _initializeMediaPlayer() async {
    if (!_hasMediaSource) {
      if (mounted) {
        setState(() {
          _isLoadingMedia = false;
          _totalDurationSec = 0;
        });
      }
      return;
    }

    try {
      final factory =
          widget.playlistPlaybackFactory ?? createLessonMediaPlaylistPlayback;
      final playback = factory();
      await playback.openSegments(lesson.mediaSegments);
      _positionSubscription = playback.globalPositionStream.listen((position) {
        _handlePlaybackPosition(
          position.floor(),
          positionSecExact: position,
        );
      });
      _durationSubscription = playback.totalDurationStream.listen((duration) {
        _updateResolvedDuration(playerDuration: Duration(seconds: duration));
      });
      _playingSubscription = playback.playingStream.listen((isPlaying) {
        _handlePlayingStreamUpdate(isPlaying);
      });

      if (!mounted) {
        await playback.close();
        return;
      }

      _applyResolvedPlaybackState(playback);
    } on LessonMediaLoadException catch (error) {
      if (mounted) {
        setState(() {
          _mediaLoadError = error.message;
          _isLoadingMedia = false;
          _totalDurationSec = 0;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _mediaLoadError = 'メディアの読み込みに失敗しました: $error';
          _isLoadingMedia = false;
          _totalDurationSec = 0;
        });
      }
    }
  }

  void _handlePlayingStreamUpdate(bool isPlaying) {
    if (!mounted) {
      return;
    }

    if (_isTeacherPreview &&
        isLessonPlaybackAtEnd(
          totalDurationSec: _totalDurationSec,
          positionSecExact: _currentPositionSecExact,
        )) {
      if (isPlaying) {
        return;
      }
      setState(() {
        _isPlaying = false;
      });
      return;
    }

    setState(() {
      _isPlaying = isPlaying;
    });
  }

  void _handlePlaybackPosition(
    int nextPositionSec, {
    required double positionSecExact,
  }) {
    if (!mounted || _totalDurationSec <= 0) {
      return;
    }

    final clampedPosition = nextPositionSec.clamp(0, _totalDurationSec);
    final clampedExact = positionSecExact
        .clamp(0.0, _totalDurationSec.toDouble())
        .toDouble();
    if (_isDraggingSlider) {
      _currentPositionSecExact = clampedExact;
      return;
    }

    final roundedSecondChanged = clampedPosition != _currentPositionSec;
    // Rebuild this page once per second. Sub-second whiteboard sync is handled
    // by [LessonPlaybackSyncedWhiteboard] so audio playback can stay smooth
    // without rebuilding the whole lesson view on every tick.
    if (!roundedSecondChanged) {
      // Still keep the exact position fresh for later comparisons (e.g.
      // end-of-lesson detection) without forcing a rebuild of the page.
      _currentPositionSecExact = clampedExact;
      return;
    }

    var shouldPersistPending = false;
    var shouldPauseTeacherPreviewAtEnd = false;
    setState(() {
      _currentPositionSecExact = clampedExact;
      final previousPositionSec = _currentPositionSec;
      if (clampedPosition != _currentPositionSec) {
        _currentPositionSec = clampedPosition;
        _addWatchProgress(previousPositionSec, _currentPositionSec);
      }
      if (_isTeacherPreview &&
          isLessonPlaybackAtEnd(
            totalDurationSec: _totalDurationSec,
            positionSecExact: clampedExact,
          )) {
        _syncPlaybackEndPosition();
        _isPlaying = false;
        shouldPauseTeacherPreviewAtEnd = true;
      }
      if (!_isTeacherPreview &&
          _currentPositionSec >= _completionThresholdSec &&
          !_pendingCompletion) {
        _setCompletionPendingState();
        shouldPersistPending = true;
      }
    });
    if (shouldPauseTeacherPreviewAtEnd) {
      unawaited(_playlistPlayback?.pause());
    }
    if (shouldPersistPending && !_isTeacherPreview) {
      unawaited(_persistSessionProgress());
    }
  }

  void _syncPlaybackEndPosition() {
    _currentPositionSec = _totalDurationSec;
    _currentPositionSecExact = _totalDurationSec.toDouble();
  }

  void _updateResolvedDuration({Duration? playerDuration}) {
    if (!mounted || _playlistPlayback == null) {
      return;
    }

    final nextTotalDurationSec = resolveTimelineDurationSec(
      timeline: _mediaTimeline,
      playerDuration: playerDuration ?? Duration(seconds: _playlistPlayback!.totalDurationSec),
      durationLabel: lesson.duration,
    );
    if (nextTotalDurationSec <= _totalDurationSec) {
      return;
    }

    setState(() {
      _totalDurationSec = nextTotalDurationSec;
      _mediaLoadError = null;
    });
  }

  void _applyResolvedPlaybackState(LessonMediaPlaylistController playback) {
    final totalDurationSec = resolveTimelineDurationSec(
      timeline: _mediaTimeline,
      playerDuration: Duration(seconds: playback.totalDurationSec),
      durationLabel: lesson.duration,
    );

    setState(() {
      _playlistPlayback = playback;
      _totalDurationSec = totalDurationSec;
      _isLoadingMedia = false;
      if (!playback.isReady) {
        _mediaLoadError = 'メディアの読み込みに失敗しました。';
      } else if (totalDurationSec <= 0) {
        _mediaLoadError = '再生時間を取得できませんでした。';
      } else {
        _mediaLoadError = null;
      }
    });
    unawaited(_reconcileOpenPlaybackPosition());
  }

  Future<void> _reconcileOpenPlaybackPosition() async {
    if (!mounted ||
        _hasReconciledOpenPlaybackPosition ||
        _isLoadingLearningState ||
        _isLoadingMedia ||
        _playlistPlayback == null ||
        _totalDurationSec <= 0 ||
        _isTeacherPreview) {
      return;
    }

    _hasReconciledOpenPlaybackPosition = true;

    final savedPositionSec = _currentPositionSec;
    final finishedPriorAttempt = _pendingCompletion ||
        savedPositionSec >= _completionThresholdSec ||
        savedPositionSec >= _totalDurationSec - 1;

    if (finishedPriorAttempt) {
      if (mounted) {
        setState(() {
          _currentPositionSec = 0;
          _currentPositionSecExact = 0;
          _pendingCompletion = false;
        });
      }
      await _playlistPlayback!.seekGlobal(0);
      if (mounted) {
        _syncDisplayedPlaybackPositionFromPlayer();
      }
      return;
    }

    if (_hasPlaybackStarted && savedPositionSec > 0) {
      await _seekMediaPlayback(savedPositionSec);
    }
  }

  Future<void> _togglePlayback() async {
    if (!_hasMediaSource || _mediaLoadError != null || _totalDurationSec <= 0) {
      setState(() {
        _message = _hasMediaSource
            ? (_mediaLoadError ?? '再生時間を取得できませんでした。')
            : '音声・動画ファイルが未設定のため再生できません。';
      });
      return;
    }

    if (_isPlaying) {
      await _pausePlayback();
      return;
    }

    if (_sessionCompleted || _isAtEnd) {
      _resetPlaybackCycleState(positionSec: 0);
      await _seekMediaPlayback(0);
    }

    final prepared = await _ensureSession(preservePlaybackPosition: true);
    if (!prepared || !mounted) {
      return;
    }

    setState(() {
      _hasPlaybackStarted = true;
      _message = null;
    });
    if (_playbackPositionDriftSec() >= _resumeSeekDriftToleranceSec) {
      await _seekMediaPlayback(_currentPositionSec);
    } else {
      _syncDisplayedPlaybackPositionFromPlayer();
    }
    await _startMediaPlayback();
  }

  void _resetPlaybackCycleState({required int positionSec}) {
    setState(() {
      _currentPositionSec = positionSec;
      _currentPositionSecExact = positionSec.toDouble();
      _sessionId = null;
      _segmentId = null;
      _sessionCompleted = false;
      _studySeconds = 0;
      _watchSeconds = 0;
      _cycleMaxWatchedPositionSec = 0;
      _hasPlaybackStarted = false;
      _pendingCompletion = false;
      _selectedChoices.clear();
      _answerResults.clear();
      _answeredQuizEventIds.clear();
      _cycleWatchedRanges.clear();
      _message = null;
    });
  }

  Future<void> _seekMediaPlayback(int positionSec) async {
    if (_playlistPlayback == null || _totalDurationSec <= 0) {
      return;
    }

    final targetPosition = positionSec.clamp(0, _totalDurationSec);
    await _playlistPlayback!.seekGlobal(targetPosition.toDouble());
    if (!mounted) {
      return;
    }

    _syncDisplayedPlaybackPositionFromPlayer();
    _startPostSeekDisplaySync();
  }

  void _syncDisplayedPlaybackPositionFromPlayer() {
    final playback = _playlistPlayback;
    if (playback == null || _totalDurationSec <= 0) {
      return;
    }

    _applyDisplayPositionFromGlobalSec(playback.liveGlobalPositionSec);
  }

  int _flooredDisplaySecForGlobal(double globalSec) {
    return globalSec.floor().clamp(0, _totalDurationSec);
  }

  double _playbackPositionDriftSec() {
    final playback = _playlistPlayback;
    if (playback == null) {
      return 0;
    }
    return (playback.liveGlobalPositionSec - _currentPositionSecExact).abs();
  }

  void _applyDisplayPositionFromGlobalSec(double globalSec) {
    final clampedGlobal = globalSec.clamp(
      0.0,
      _totalDurationSec.toDouble(),
    );
    setState(() {
      _currentPositionSec = _flooredDisplaySecForGlobal(clampedGlobal);
      _currentPositionSecExact = clampedGlobal;
    });
  }

  void _startPostSeekDisplaySync() {
    _postSeekDisplaySyncTimer?.cancel();
    var ticks = 0;
    _postSeekDisplaySyncTimer = Timer.periodic(
      _postSeekDisplaySyncInterval,
      (timer) {
        if (!mounted) {
          timer.cancel();
          _postSeekDisplaySyncTimer = null;
          return;
        }

        ticks += 1;
        if (ticks > _postSeekDisplaySyncTickCount) {
          timer.cancel();
          _postSeekDisplaySyncTimer = null;
          return;
        }

        final playback = _playlistPlayback;
        if (playback == null || _totalDurationSec <= 0 || _isDraggingSlider) {
          return;
        }

        final globalSec = playback.liveGlobalPositionSec
            .clamp(0.0, _totalDurationSec.toDouble());
        final nextSec = _flooredDisplaySecForGlobal(globalSec);
        if (nextSec == _currentPositionSec) {
          return;
        }

        setState(() {
          _currentPositionSec = nextSec;
          _currentPositionSecExact = globalSec;
        });
      },
    );
  }

  Future<void> _startMediaPlayback() async {
    try {
      await _playlistPlayback?.play();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _message = '再生に失敗しました: $error';
        });
      }
    }
  }

  Future<void> _pausePlayback() async {
    _playbackTimer?.cancel();
    await _playlistPlayback?.pause();
    if (mounted) {
      _syncDisplayedPlaybackPositionFromPlayer();
      setState(() {
        _isPlaying = false;
      });
    }
  }

  Future<void> _seekPlaybackPosition(int positionSec) async {
    if (_totalDurationSec <= 0) {
      return;
    }
    final nextPosition = positionSec.clamp(0, _totalDurationSec);
    await _seekMediaPlayback(nextPosition);
    if (!mounted) {
      return;
    }

    setState(() {
      _message = null;
      if (_pendingCompletion && nextPosition < _completionThresholdSec) {
        _pendingCompletion = false;
      }
    });
    if (!_isTeacherPreview) {
      unawaited(_persistSessionProgress());
    }
  }

  Future<void> _seekForDevelopment(int deltaSeconds) async {
    if (deltaSeconds == 0) {
      return;
    }

    if (!_hasActiveSession && _currentPositionSec == 0 && deltaSeconds < 0) {
      return;
    }

    _seekPlaybackPosition(_currentPositionSec + deltaSeconds);
  }

  String _courseId() {
    return course.storageId;
  }

  void _listenEntryRequirement() {
    if (_isTeacherPreview || Firebase.apps.isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    _entryRequirementSubscription?.cancel();
    _entryRequirementSubscription = const CoursePrivacyService()
        .watchEntryRequirement(userId: user.uid, courseId: _courseId())
        .listen((requirement) {
          if (!mounted || _isHandlingEntryRequirementBlock) {
            return;
          }
          if (!requirement.isResolved) {
            return;
          }
          if (requirement.canEnter) {
            return;
          }
          _isHandlingEntryRequirementBlock = true;
          final message = requirement.policy.shareAmongLearnersEnabled
              ? '講座設定が更新され、受講者同士の本名公開を含む同意が必要になりました。'
              : '講座設定が更新され、先生への本名提供の同意が必要になりました。';
          unawaited(
            () async {
              unawaited(_pausePlayback());
              final canContinue = await showCoursePolicyBlockDialog(
                context,
                course: course,
                message: '$message\n同意しない場合は講座画面から退出します。',
              );
              if (!mounted) {
                return;
              }
              if (!canContinue) {
                Navigator.of(context).pop();
                return;
              }
              _isHandlingEntryRequirementBlock = false;
            }().whenComplete(() {
              _isHandlingEntryRequirementBlock = false;
            }),
          );
        });
  }

  DocumentReference<Map<String, dynamic>> _activeLearningLockRef(User user) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('activeLearningSession')
        .doc(_activeLearningSessionDocId);
  }

  ActiveLearningLockSnapshot? _activeLearningLockSnapshotFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    final lastHeartbeatAt = data['lastHeartbeatAt'];
    return ActiveLearningLockSnapshot(
      deviceId: data['deviceId'] as String?,
      status: data['status'] as String?,
      lastHeartbeatAt: lastHeartbeatAt is Timestamp
          ? lastHeartbeatAt.toDate()
          : null,
    );
  }

  Map<String, dynamic> _activeLearningLockData({
    required String userId,
    required String sessionId,
    required String status,
    required FieldValue now,
  }) {
    return {
      'userId': userId,
      'deviceId': _activeLearningDeviceId,
      'sessionId': sessionId,
      'segmentId': _segmentId ?? '',
      'courseId': _courseId(),
      'courseTitle': course.title,
      'lessonNumber': lessonNumber,
      'lessonTitle': lesson.title,
      'cycleNumber': _cycleNumber,
      'status': status,
      'lastHeartbeatAt': now,
      'updatedAt': now,
    };
  }

  Future<bool> _acquireActiveLearningLock(User user, String sessionId) async {
    final lockRef = _activeLearningLockRef(user);
    final acquired = await FirebaseFirestore.instance.runTransaction<bool>((
      transaction,
    ) async {
      final snapshot = await transaction.get(lockRef);
      final decision = decideActiveLearningLock(
        existingLock: _activeLearningLockSnapshotFromDoc(snapshot),
        currentDeviceId: _activeLearningDeviceId,
        now: DateTime.now(),
        staleAfter: _activeLearningLockStaleAfter,
      );
      if (!decision.canAcquire) {
        return false;
      }

      final now = FieldValue.serverTimestamp();
      transaction.set(
        lockRef,
        _activeLearningLockData(
          userId: user.uid,
          sessionId: sessionId,
          status: 'active',
          now: now,
        ),
        SetOptions(merge: true),
      );
      return true;
    });

    if (acquired) {
      _hasActiveLearningLock = true;
      _startActiveLearningHeartbeat();
    }
    return acquired;
  }

  void _startActiveLearningHeartbeat() {
    _activeLearningHeartbeatTimer?.cancel();
    _activeLearningHeartbeatTimer = Timer.periodic(
      _activeLearningHeartbeatInterval,
      (_) => unawaited(_sendActiveLearningHeartbeat()),
    );
  }

  Future<void> _sendActiveLearningHeartbeat() async {
    final sessionId = _sessionId;
    if (!_hasActiveLearningLock || sessionId == null || Firebase.apps.isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final lockRef = _activeLearningLockRef(user);
    final stillOwnsLock = await FirebaseFirestore.instance.runTransaction<bool>(
      (transaction) async {
        final snapshot = await transaction.get(lockRef);
        final data = snapshot.data();
        if (data != null &&
            data['status'] == 'active' &&
            data['deviceId'] != _activeLearningDeviceId) {
          return false;
        }

        final now = FieldValue.serverTimestamp();
        transaction.set(
          lockRef,
          _activeLearningLockData(
            userId: user.uid,
            sessionId: sessionId,
            status: 'active',
            now: now,
          ),
          SetOptions(merge: true),
        );
        return true;
      },
    );

    if (!stillOwnsLock) {
      _handleActiveLearningLockLost();
    }
  }

  void _handleActiveLearningLockLost() {
    _hasActiveLearningLock = false;
    _activeLearningHeartbeatTimer?.cancel();
    _playbackTimer?.cancel();
    _studyTimer?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _isPlaying = false;
      _message = '別の端末で学習が開始されたため、この端末での再生を停止しました。';
    });
  }

  Future<void> _releaseActiveLearningLock() async {
    final sessionId = _sessionId;
    if (!_hasActiveLearningLock || sessionId == null || Firebase.apps.isEmpty) {
      return;
    }

    _hasActiveLearningLock = false;
    _activeLearningHeartbeatTimer?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final lockRef = _activeLearningLockRef(user);
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(lockRef);
      final data = snapshot.data();
      if (data == null ||
          data['deviceId'] != _activeLearningDeviceId ||
          data['sessionId'] != sessionId) {
        return;
      }

      final now = FieldValue.serverTimestamp();
      transaction.set(lockRef, {
        'status': 'inactive',
        'lastHeartbeatAt': now,
        'endedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _resumeActiveLearningAfterLifecycle() async {
    if (Firebase.apps.isEmpty) {
      _startStudyTimer();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final sessionId = _sessionId;
    if (user == null || sessionId == null) {
      return;
    }

    final acquired = await _acquireActiveLearningLock(user, sessionId);
    if (!mounted) {
      return;
    }
    if (acquired) {
      _startStudyTimer();
      return;
    }

    setState(() {
      _isPlaying = false;
      _message = '別の端末で学習中のため、この端末では同時に再生できません。';
    });
  }

  Future<bool> _ensureSession({bool preservePlaybackPosition = false}) async {
    if (_isTeacherPreview) {
      _startTeacherPreviewSession();
      return true;
    }
    if (_hasActiveSession && _segmentId != null) {
      if (Firebase.apps.isNotEmpty && !_hasActiveLearningLock) {
        final user = FirebaseAuth.instance.currentUser;
        final sessionId = _sessionId;
        if (user != null && sessionId != null) {
          final acquired = await _acquireActiveLearningLock(user, sessionId);
          if (!acquired) {
            if (mounted) {
              setState(() {
                _message = '別の端末で学習中のため、この端末では同時に再生できません。';
              });
            }
            return false;
          }
        }
      }
      _startStudyTimer();
      return true;
    }

    setState(() {
      _isPreparingSession = true;
      _message = null;
    });

    try {
      if (Firebase.apps.isEmpty) {
        _startLocalSession();
        return true;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _startLocalSession();
        return true;
      }

      final session = await _loadOrCreateCycleSession(
        user,
        preservePlaybackPosition: preservePlaybackPosition,
      );
      final acquired = await _acquireActiveLearningLock(user, session.id);
      if (!acquired) {
        if (mounted) {
          setState(() {
            _message = '別の端末で学習中のため、この端末では同時に再生できません。';
          });
        }
        return false;
      }
      await _loadOrCreateSegment(user, session);
      await _sendActiveLearningHeartbeat();
      await _refreshDisplayedCycleNumber(user);
      _startStudyTimer();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '学習記録の準備に失敗しました。後でもう一度お試しください。';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingSession = false;
        });
      }
    }
  }

  void _startTeacherPreviewSession() {
    if (_hasActiveSession && _segmentId != null) {
      return;
    }
    _sessionId = 'teacher-preview';
    _segmentId = 'teacher-preview-segment';
    _cycleNumber = 1;
    _displayCycleNumber = 1;
    _sessionCompleted = false;
    _studySeconds = 0;
    _watchSeconds = 0;
    _cycleMaxWatchedPositionSec = 0;
    _hasPlaybackStarted = true;
    _pendingCompletion = false;
    _answeredQuizEventIds.clear();
    _cycleWatchedRanges.clear();
  }

  void _startLocalSession() {
    _sessionId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    _segmentId = 'local-segment-${DateTime.now().microsecondsSinceEpoch}';
    _cycleNumber = _sessionCompleted ? _cycleNumber + 1 : _cycleNumber;
    _displayCycleNumber = _cycleNumber;
    _sessionCompleted = false;
    _studySeconds = 0;
    _watchSeconds = 0;
    _cycleMaxWatchedPositionSec = 0;
    _hasPlaybackStarted = true;
    _pendingCompletion = false;
    _answeredQuizEventIds.clear();
    _cycleWatchedRanges.clear();
    _startStudyTimer();
  }

  void _loadSession(
    String sessionId,
    Map<String, dynamic> data, {
    bool preserveCurrentPosition = false,
  }) {
    _sessionId = sessionId;
    _cycleNumber = (data['cycleNumber'] as num?)?.toInt() ?? 1;
    _displayCycleNumber ??= _cycleNumber;
    _sessionCompleted =
        data['status'] == 'completed' || data['cycleCompleted'] == true;
    _cycleMaxWatchedPositionSec =
        (data['maxWatchedPositionSec'] as num?)?.toInt() ??
        (data['maxPositionSec'] as num?)?.toInt() ??
        0;
    if (!preserveCurrentPosition) {
      _currentPositionSec = _cycleMaxWatchedPositionSec;
      _currentPositionSecExact = _cycleMaxWatchedPositionSec.toDouble();
    }
    _hasPlaybackStarted = data['hasPlaybackStarted'] == true;
    _pendingCompletion = data['pendingCompletion'] == true;
    final answered = data['answeredQuizEventIds'];
    _answeredQuizEventIds
      ..clear()
      ..addAll(answered is List ? answered.whereType<String>() : const []);
    final watchedRanges = data['watchedRanges'];
    final legacyWatchedIndexes = data['watchedSecondIndexes'];
    _cycleWatchedRanges
      ..clear()
      ..addAll(
        watchedRanges is List
            ? watchedRangesFromFirestore(watchedRanges)
            : watchedIndexesToRanges(
                legacyWatchedIndexes is List
                    ? legacyWatchedIndexes.whereType<num>().map(
                        (second) => second.toInt(),
                      )
                    : const <int>[],
              ),
      );
  }

  Future<void> _resumeLearningTimeOnOpen() async {
    if (Firebase.apps.isEmpty) {
      _finishLearningStateLoading();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _finishLearningStateLoading();
      return;
    }

    try {
      final session = await _latestCycleSession(user);
      if (session == null) {
        await _refreshDisplayedCycleNumber(user);
        return;
      }

      final data = session.data();
      final isCompleted =
          data['status'] == 'completed' || data['cycleCompleted'] == true;
      final hasPlaybackStarted = data['hasPlaybackStarted'] == true;
      if (isCompleted) {
        _cycleNumber = ((data['cycleNumber'] as num?)?.toInt() ?? 0) + 1;
        await _refreshDisplayedCycleNumber(user);
        return;
      }
      if (!hasPlaybackStarted) {
        _loadSession(session.id, data, preserveCurrentPosition: true);
        await _refreshDisplayedCycleNumber(user);
        return;
      }

      _loadSession(session.id, data);
      final acquired = await _acquireActiveLearningLock(user, session.id);
      if (!acquired) {
        if (mounted) {
          setState(() {
            _message = '別の端末で学習中のため、この端末では同時に再生できません。';
          });
        }
        return;
      }
      await _loadOrCreateSegment(user, session);
      await _sendActiveLearningHeartbeat();
      await _refreshDisplayedCycleNumber(user);
      _startStudyTimer();
    } catch (_) {
      // Opening the page should still work even if record resume fails.
    } finally {
      _finishLearningStateLoading();
    }
  }

  void _finishLearningStateLoading() {
    if (!mounted || !_isLoadingLearningState) {
      return;
    }
    setState(() {
      _isLoadingLearningState = false;
    });
    unawaited(_reconcileOpenPlaybackPosition());
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _latestCycleSession(
    User user,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonViewSessions')
        .where('courseId', isEqualTo: _courseId())
        .where('lessonNumber', isEqualTo: lessonNumber)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final sessions = snapshot.docs.toList()
      ..sort((a, b) {
        final aCycle = (a.data()['cycleNumber'] as num?)?.toInt() ?? 0;
        final bCycle = (b.data()['cycleNumber'] as num?)?.toInt() ?? 0;
        if (aCycle != bCycle) {
          return bCycle.compareTo(aCycle);
        }
        final aStartedAt = a.data()['startedAt'];
        final bStartedAt = b.data()['startedAt'];
        if (aStartedAt is Timestamp && bStartedAt is Timestamp) {
          return bStartedAt.compareTo(aStartedAt);
        }
        return 0;
      });

    return sessions.first;
  }

  Future<void> _refreshDisplayedCycleNumber(User user) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonViewSegments')
        .where('courseId', isEqualTo: _courseId())
        .where('lessonNumber', isEqualTo: lessonNumber)
        .get();

    final displayCycleNumber = displayedCycleNumber(
      actualCycleNumber: _cycleNumber,
      records: snapshot.docs.map((doc) {
        final data = doc.data();
        return LessonCycleDisplayRecord(
          cycleNumber: (data['cycleNumber'] as num?)?.toInt() ?? 1,
          isDeleted: data['isDeleted'] == true,
        );
      }),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _displayCycleNumber = displayCycleNumber;
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadOrCreateCycleSession(
    User user, {
    bool preservePlaybackPosition = false,
  }) async {
    final sessionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonViewSessions');
    final latest = await _latestCycleSession(user);

    if (latest != null) {
      final latestData = latest.data();
      final isCompleted =
          latestData['status'] == 'completed' ||
          latestData['cycleCompleted'] == true;
      if (!isCompleted) {
        _loadSession(
          latest.id,
          latestData,
          preserveCurrentPosition: preservePlaybackPosition,
        );
        await latest.reference.set({
          'hasPlaybackStarted': true,
          'lastActivityAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _hasPlaybackStarted = true;
        return latest;
      }

      _cycleNumber = ((latestData['cycleNumber'] as num?)?.toInt() ?? 0) + 1;
    }

    final newSessionRef = sessionsRef.doc();
    final startedAt = FieldValue.serverTimestamp();
    await newSessionRef.set({
      'userId': user.uid,
      'courseId': _courseId(),
      'courseTitle': course.title,
      'lessonNumber': lessonNumber,
      'lessonTitle': lesson.title,
      'cycleNumber': _cycleNumber,
      'status': 'inProgress',
      'cycleCompleted': false,
      'pendingCompletion': false,
      'hasPlaybackStarted': true,
      'startedAt': startedAt,
      'lastActivityAt': startedAt,
      'maxWatchedPositionSec': 0,
      'totalDurationSec': _totalDurationSec,
      'completionThresholdSec': _completionThresholdSec,
      'answeredQuizEventIds': [],
      'watchedRanges': [],
    });

    final created = await newSessionRef.get();
    _loadSession(created.id, created.data()!, preserveCurrentPosition: true);
    return created;
  }

  LearningTaskSnapshot? _learningTaskSnapshotFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    final sessionId = data['sessionId'];
    final segmentId = data['segmentId'];
    if (sessionId is! String || segmentId is! String) {
      return null;
    }

    final lastActivityAt = data['lastActivityAt'];
    return LearningTaskSnapshot(
      sessionId: sessionId,
      segmentId: segmentId,
      lastActivityAt: lastActivityAt is Timestamp
          ? lastActivityAt.toDate()
          : null,
    );
  }

  ActiveSegmentSnapshot? _activeSegmentSnapshotFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    return ActiveSegmentSnapshot(
      status: data['status'] as String?,
      isDeleted: data['isDeleted'] == true,
    );
  }

  void _setLearningTaskState(
    WriteBatch batch,
    DocumentReference<Map<String, dynamic>> userRef, {
    required String userId,
    required String sessionId,
    required String segmentId,
    required FieldValue lastActivityAt,
    required String status,
  }) {
    batch.set(
      userRef.collection('learningTaskState').doc(_learningTaskStateDocId),
      {
        'userId': userId,
        'taskKey': _taskKey,
        'sessionId': sessionId,
        'segmentId': segmentId,
        'courseId': _courseId(),
        'courseTitle': course.title,
        'lessonNumber': lessonNumber,
        'lessonTitle': lesson.title,
        'cycleNumber': _cycleNumber,
        'status': status,
        'lastActivityAt': lastActivityAt,
        'updatedAt': lastActivityAt,
      },
      SetOptions(merge: true),
    );
  }

  void _addLearningTaskEvent(
    WriteBatch batch,
    DocumentReference<Map<String, dynamic>> userRef, {
    required String userId,
    required String sessionId,
    required String segmentId,
    required String eventType,
    required FieldValue occurredAt,
    SegmentBoundaryReason? boundaryReason,
  }) {
    batch.set(userRef.collection('learningTaskEvents').doc(), {
      'userId': userId,
      'taskKey': _taskKey,
      'sessionId': sessionId,
      'segmentId': segmentId,
      'courseId': _courseId(),
      'courseTitle': course.title,
      'lessonNumber': lessonNumber,
      'lessonTitle': lesson.title,
      'cycleNumber': _cycleNumber,
      'eventType': eventType,
      if (boundaryReason != null)
        'boundaryReason': segmentBoundaryReasonName(boundaryReason),
      'occurredAt': occurredAt,
    });
  }

  Future<void> _loadOrCreateSegment(
    User user,
    DocumentSnapshot<Map<String, dynamic>> session,
  ) async {
    final now = DateTime.now();
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final segmentsRef = userRef.collection('lessonViewSegments');
    final taskStateDoc = await userRef
        .collection('learningTaskState')
        .doc(_learningTaskStateDocId)
        .get();
    final previousTask = _learningTaskSnapshotFromDoc(taskStateDoc);
    DocumentSnapshot<Map<String, dynamic>>? activeSegmentDoc;

    if (previousTask != null && previousTask.sessionId == session.id) {
      activeSegmentDoc = await segmentsRef.doc(previousTask.segmentId).get();
    }

    final decision = decideSegmentBoundary(
      previousTask: previousTask,
      activeSegment: activeSegmentDoc == null
          ? null
          : _activeSegmentSnapshotFromDoc(activeSegmentDoc),
      currentSessionId: session.id,
      now: now,
      resumeWindow: _resumeWindow,
    );

    if (decision.shouldResume && activeSegmentDoc != null) {
      final latestData = activeSegmentDoc.data()!;
      _segmentId = activeSegmentDoc.id;
      _studySeconds = (latestData['studySeconds'] as num?)?.toInt() ?? 0;
      _watchSeconds = (latestData['watchSeconds'] as num?)?.toInt() ?? 0;

      final serverNow = FieldValue.serverTimestamp();
      final batch = FirebaseFirestore.instance.batch();
      _setLearningTaskState(
        batch,
        userRef,
        userId: user.uid,
        sessionId: session.id,
        segmentId: activeSegmentDoc.id,
        lastActivityAt: serverNow,
        status: 'inProgress',
      );
      _addLearningTaskEvent(
        batch,
        userRef,
        userId: user.uid,
        sessionId: session.id,
        segmentId: activeSegmentDoc.id,
        eventType: 'segmentResumed',
        occurredAt: serverNow,
        boundaryReason: decision.reason,
      );
      await batch.commit();
      return;
    }

    final newSegmentRef = segmentsRef.doc();
    final serverNow = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();
    batch.set(newSegmentRef, {
      'userId': user.uid,
      'sessionId': session.id,
      'courseId': _courseId(),
      'courseTitle': course.title,
      'lessonNumber': lessonNumber,
      'lessonTitle': lesson.title,
      'cycleNumber': _cycleNumber,
      'taskKey': _taskKey,
      'status': 'inProgress',
      'startedAt': serverNow,
      'lastActivityAt': serverNow,
      'studySeconds': 0,
      'watchSeconds': 0,
      'startPositionSec': _cycleMaxWatchedPositionSec,
      'endPositionSec': _cycleMaxWatchedPositionSec,
      'isDeleted': false,
    });
    _setLearningTaskState(
      batch,
      userRef,
      userId: user.uid,
      sessionId: session.id,
      segmentId: newSegmentRef.id,
      lastActivityAt: serverNow,
      status: 'inProgress',
    );
    _addLearningTaskEvent(
      batch,
      userRef,
      userId: user.uid,
      sessionId: session.id,
      segmentId: newSegmentRef.id,
      eventType: 'segmentStarted',
      occurredAt: serverNow,
      boundaryReason: decision.reason,
    );
    await batch.commit();
    _segmentId = newSegmentRef.id;
    _studySeconds = 0;
    _watchSeconds = 0;
  }

  void _startStudyTimer() {
    if (_sessionCompleted || _studyTimer?.isActive == true) {
      return;
    }

    _studyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sessionCompleted) {
        _studyTimer?.cancel();
        return;
      }
      setState(() {
        _studySeconds += 1;
      });
    });
  }

  void _addWatchProgress(int fromPositionSec, int toPositionSec) {
    if (toPositionSec <= fromPositionSec) {
      return;
    }

    final startSec = fromPositionSec.clamp(0, _totalDurationSec).toInt();
    final endSec = toPositionSec.clamp(0, _totalDurationSec).toInt();
    final addedWatchSeconds = watchedSecondsAddedByRange(
      _cycleWatchedRanges,
      startSec: startSec,
      endSec: endSec,
    );
    final updatedRanges = addWatchedRange(
      _cycleWatchedRanges,
      startSec: startSec,
      endSec: endSec,
    );
    _cycleWatchedRanges
      ..clear()
      ..addAll(updatedRanges);
    _watchSeconds += addedWatchSeconds;
    _cycleMaxWatchedPositionSec = maxWatchedPositionSec(_cycleWatchedRanges);
  }

  Future<void> _persistSessionProgress() async {
    final sessionId = _sessionId;
    final segmentId = _segmentId;
    if (sessionId == null || segmentId == null || Firebase.apps.isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch()
      ..set(
        userRef.collection('lessonViewSessions').doc(sessionId),
        {
          'lastActivityAt': now,
          'maxWatchedPositionSec': _cycleMaxWatchedPositionSec,
          'pendingCompletion': _pendingCompletion,
          'hasPlaybackStarted': _hasPlaybackStarted,
          'answeredQuizEventIds': _answeredQuizEventIds.toList(),
          'watchedRanges': watchedRangesToFirestore(_cycleWatchedRanges),
        },
        SetOptions(merge: true),
      )
      ..set(
        userRef.collection('lessonViewSegments').doc(segmentId),
        {
          'lastActivityAt': now,
          'studySeconds': _studySeconds,
          'watchSeconds': _watchSeconds,
          'endPositionSec': _cycleMaxWatchedPositionSec,
        },
        SetOptions(merge: true),
      );
    _setLearningTaskState(
      batch,
      userRef,
      userId: user.uid,
      sessionId: sessionId,
      segmentId: segmentId,
      lastActivityAt: now,
      status: 'inProgress',
    );

    await batch.commit();
  }

  void _setCompletionPendingState() {
    _playbackTimer?.cancel();
    _isPlaying = false;
    unawaited(_playlistPlayback?.pause());
    _currentPositionSec = _currentPositionSec
        .clamp(_completionThresholdSec, _totalDurationSec)
        .toInt();
    _pendingCompletion = true;
    _message = '視聴終了地点に到達しました。画面を離れた時刻を終了日時として記録します。';
  }

  Future<void> _completeCurrentSegment({bool updateUi = true}) async {
    if (_sessionCompleted) {
      return;
    }

    _playbackTimer?.cancel();
    _studyTimer?.cancel();
    void updateState() {
      _isPlaying = false;
      _sessionCompleted = true;
      _pendingCompletion = false;
      _message = 'レッスン$lessonNumber $_cycleNumber周目終了として記録しました。';
    }

    if (updateUi && mounted) {
      setState(updateState);
    } else {
      updateState();
    }

    final sessionId = _sessionId;
    final segmentId = _segmentId;
    if (sessionId == null || segmentId == null || Firebase.apps.isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch()
      ..set(
        userRef.collection('lessonViewSessions').doc(sessionId),
        {
          'status': 'completed',
          'cycleCompleted': true,
          'pendingCompletion': false,
          'completedAt': now,
          'lastActivityAt': now,
          'maxWatchedPositionSec': _cycleMaxWatchedPositionSec,
          'answeredQuizEventIds': _answeredQuizEventIds.toList(),
          'watchedRanges': watchedRangesToFirestore(_cycleWatchedRanges),
        },
        SetOptions(merge: true),
      )
      ..set(
        userRef.collection('lessonViewSegments').doc(segmentId),
        {
          'status': 'completed',
          'completedAt': now,
          'lastActivityAt': now,
          'studySeconds': _studySeconds,
          'watchSeconds': _watchSeconds,
          'endPositionSec': _cycleMaxWatchedPositionSec,
        },
        SetOptions(merge: true),
      );
    _setLearningTaskState(
      batch,
      userRef,
      userId: user.uid,
      sessionId: sessionId,
      segmentId: segmentId,
      lastActivityAt: now,
      status: 'completed',
    );
    _addLearningTaskEvent(
      batch,
      userRef,
      userId: user.uid,
      sessionId: sessionId,
      segmentId: segmentId,
      eventType: 'segmentCompleted',
      occurredAt: now,
    );

    await batch.commit();
    await _releaseActiveLearningLock();
  }

  Future<void> _completeManually() async {
    if (_isTeacherPreview) {
      setState(() {
        _message = '先生プレビュー中は学習記録を保存しません。';
      });
      return;
    }
    final prepared = await _ensureSession();
    if (!prepared || !mounted) {
      return;
    }
    await _completeCurrentSegment();
  }

  Future<void> _submitAnswer(LessonEvent event) async {
    if (_isTeacherPreview) {
      setState(() {
        _message = '先生プレビュー中はクイズ回答を保存しません。';
      });
      return;
    }
    if (_answeredQuizEventIds.contains(event.id)) {
      setState(() {
        _message = 'この周では回答済みです。';
      });
      return;
    }

    final prepared = await _ensureSession();
    if (!prepared || !mounted) {
      return;
    }

    final selectedChoiceIndex = _selectedChoices[event.id];
    final quiz = event.quiz;
    if (selectedChoiceIndex == null || quiz == null) {
      setState(() {
        _message = '回答を選択してください。';
      });
      return;
    }

    final isCorrect = selectedChoiceIndex == quiz.correctChoiceIndex;

    try {
      final saveOverride = widget.onQuizAnswerSaveOverride;
      if (saveOverride != null) {
        await saveOverride(
          event: event,
          selectedChoiceIndex: selectedChoiceIndex,
          isCorrect: isCorrect,
        );
      } else {
        await _saveQuizAnswer(
          event: event,
          selectedChoiceIndex: selectedChoiceIndex,
          isCorrect: isCorrect,
        );
      }

      if (mounted) {
        setState(() {
          _answerResults[event.id] = isCorrect;
          _answeredQuizEventIds.add(event.id);
          _message = isCorrect ? '正解です。' : '不正解です。解説を確認しましょう。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '回答の保存に失敗しました。後でもう一度お試しください。';
        });
      }
    }
  }

  Future<void> _saveQuizAnswer({
    required LessonEvent event,
    required int selectedChoiceIndex,
    required bool isCorrect,
  }) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final quiz = event.quiz;
    if (quiz == null) {
      return;
    }

    final courseId = course.storageId;
    final sessionId = _sessionId;
    final cycleQuizKey = buildCycleQuizKey(
      courseId: courseId,
      lessonNumber: lessonNumber,
      cycleNumber: _cycleNumber,
      eventId: event.id,
      sessionId: sessionId,
    );
    final firestore = FirebaseFirestore.instance;
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('quizAttempts')
        .add({
          'userId': user.uid,
          'courseId': courseId,
          'courseTitle': course.title,
          'lessonNumber': lessonNumber,
          'lessonTitle': lesson.title,
          'sessionId': sessionId,
          'cycleNumber': _cycleNumber,
          'cycleQuizKey': cycleQuizKey,
          'eventId': event.id,
          'question': quiz.question,
          'selectedChoiceIndex': selectedChoiceIndex,
          'correctChoiceIndex': quiz.correctChoiceIndex,
          'isCorrect': isCorrect,
          'answeredAt': FieldValue.serverTimestamp(),
        });

    if (sessionId != null) {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('lessonViewSessions')
          .doc(sessionId)
          .set({
            'answeredQuizEventIds': FieldValue.arrayUnion([event.id]),
          }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusMessage =
        _message ??
        (_pendingCompletion ? '視聴終了地点に到達しました。画面を離れた時刻を終了日時として記録します。' : null);
    final cycleLabel = _isLoadingLearningState ? 'ー' : '$_visibleCycleNumber周目';
    final studySecondsLabel = _isLoadingLearningState ? 'ー' : '$_studySeconds秒';
    final watchSecondsLabel = _isLoadingLearningState ? 'ー' : '$_watchSeconds秒';

    final canControlPlayback = _hasMediaSource &&
        _mediaLoadError == null &&
        _totalDurationSec > 0 &&
        (_playlistPlayback?.isReady ?? false);
    final sliderMax = _totalDurationSec > 0 ? _totalDurationSec.toDouble() : 1.0;
    final videoController = _playlistPlayback?.videoController;
    final orderedSegments = _mediaTimeline.orderedSegments;
    final currentSegment = _playlistPlayback?.currentSegment;
    final pageTitle = orderedSegments.isEmpty
        ? 'レッスン視聴'
        : orderedSegments.every((segment) => segment.isAudio)
        ? '音声授業'
        : orderedSegments.every((segment) => segment.isVideo)
        ? '動画視聴'
        : 'レッスン視聴';

    return Scaffold(
      appBar: AppBar(title: Text(pageTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 260),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_hasMediaSource) ...[
                      Icon(
                        Icons.perm_media_outlined,
                        size: 72,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'メディアファイルが未設定です',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '先生がレッスン管理画面から音声・動画をアップロードすると、ここで再生できます。',
                        textAlign: TextAlign.center,
                      ),
                    ] else if (_isLoadingMedia) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('メディアを読み込み中…'),
                    ] else if (_mediaLoadError != null) ...[
                      Icon(
                        Icons.error_outline,
                        size: 72,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _mediaLoadError!,
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      if (!_currentSegmentIsAudio &&
                          videoController != null &&
                          videoController.value.isInitialized) ...[
                        AspectRatio(
                          aspectRatio: videoController.value.aspectRatio,
                          child: VideoPlayer(videoController),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Icon(
                          _currentSegmentIsAudio
                              ? Icons.headphones
                              : Icons.smart_display,
                          size: 72,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentSegmentIsAudio ? '音声プレイヤー' : '動画プレイヤー',
                        ),
                        if (currentSegment != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            currentSegment.title.isNotEmpty
                                ? currentSegment.title
                                : 'パート${(_playlistPlayback?.currentSegmentIndex ?? 0) + 1}',
                          ),
                        ],
                        const SizedBox(height: 4),
                        const Text('アップロード済みのファイルを再生します。'),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        '${formatLessonTime(_displayedPositionSec)} / ${formatLessonTime(_totalDurationSec)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Slider(
                          value: (_sliderDragPositionSec ??
                                  _currentPositionSec.toDouble())
                              .clamp(0, _totalDurationSec)
                              .toDouble(),
                          min: 0,
                          max: sliderMax,
                          divisions: _totalDurationSec > 0 ? _totalDurationSec : null,
                          label: formatLessonTime(_displayedPositionSec),
                          onChangeStart: canControlPlayback
                              ? (_) {
                                  setState(() {
                                    _sliderDragPositionSec =
                                        _currentPositionSec.toDouble();
                                  });
                                }
                              : null,
                          onChanged: canControlPlayback
                              ? (value) {
                                  setState(() {
                                    _sliderDragPositionSec = value;
                                  });
                                }
                              : null,
                          onChangeEnd: canControlPlayback
                              ? (value) {
                                  final targetSec = value
                                      .round()
                                      .clamp(0, _totalDurationSec);
                                  setState(() {
                                    _sliderDragPositionSec = null;
                                    _currentPositionSec = targetSec;
                                    _currentPositionSecExact =
                                        targetSec.toDouble();
                                  });
                                  unawaited(_seekPlaybackPosition(targetSec));
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: !canControlPlayback || _isPreparingSession
                            ? null
                            : () {
                                unawaited(_togglePlayback());
                              },
                        icon: Icon(_playButtonIcon),
                        label: Text(_playButtonLabel),
                      ),
                      if (orderedSegments.length > 1) ...[
                        const SizedBox(height: 16),
                        Text(
                          'パート移動',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in orderedSegments.indexed)
                              OutlinedButton(
                                onPressed: !canControlPlayback
                                    ? null
                                    : () {
                                        unawaited(
                                          _playlistPlayback?.seekToSegmentIndex(
                                            entry.$1,
                                          ),
                                        );
                                      },
                                child: Text(
                                  entry.$2.title.isNotEmpty
                                      ? entry.$2.title
                                      : 'パート${entry.$1 + 1}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            if (_hasWhiteboard) ...[
              const SizedBox(height: 16),
              Text(
                'ホワイトボード',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              LessonPlaybackSyncedWhiteboard(
                bundle: lesson.publishedWhiteboardBundle,
                timeline: _mediaTimeline,
                playback: _playlistPlayback,
                isPlaying: _isPlaying,
                positionSecExact: _currentPositionSecExact,
                totalDurationSec: _totalDurationSec,
              ),
            ],
            const SizedBox(height: 24),
            Text(course.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'レッスン$lessonNumber: ${lesson.title}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (_isTeacherPreview) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '先生プレビュー中です。講座内容と公開欄だけを確認でき、'
                    '自分のメモ・質問投稿・学習記録は使いません。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text('再生時間: ${lesson.duration}'),
            const SizedBox(height: 8),
            Text(
              'パート数: ${orderedSegments.length} / 合計 ${formatLessonTime(_totalDurationSec)}',
            ),
            if (_hasMediaSource) ...[
              const SizedBox(height: 8),
              Text('再生時間（ファイル）: ${formatLessonTime(_totalDurationSec)}'),
            ],
            const SizedBox(height: 8),
            Text('現在位置: ${formatLessonTime(_currentPositionSec)}'),
            if (!_isTeacherPreview && canControlPlayback) ...[
              const SizedBox(height: 8),
              Text('現在の周回: $cycleLabel'),
              const SizedBox(height: 8),
              Text('学習時間: $studySecondsLabel'),
              const SizedBox(height: 8),
              Text('視聴時間: $watchSecondsLabel'),
              const SizedBox(height: 8),
              Text('視聴終了判定: $_completionThresholdSec秒到達'),
            ],
            if (canControlPlayback && kDebugMode) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_seekForDevelopment(1));
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('1秒進める（開発用）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_seekForDevelopment(5));
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('5秒進める（開発用）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_seekForDevelopment(30));
                    },
                    icon: const Icon(Icons.forward_30),
                    label: const Text('30秒進める（開発用）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_seekForDevelopment(-1));
                    },
                    icon: const Icon(Icons.remove),
                    label: const Text('1秒巻き戻す（開発用）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_seekForDevelopment(-5));
                    },
                    icon: const Icon(Icons.remove),
                    label: const Text('5秒巻き戻す（開発用）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_seekForDevelopment(-30));
                    },
                    icon: const Icon(Icons.replay_30),
                    label: const Text('30秒巻き戻す（開発用）'),
                  ),
                ],
              ),
            ],
            if (!_isTeacherPreview && canControlPlayback) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _sessionCompleted
                    ? null
                    : () {
                        unawaited(_completeManually());
                      },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('視聴終了として記録'),
              ),
            ],
            if (kDebugMode && orderedSegments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'segments: ${orderedSegments.map((segment) => segment.id).join(', ')}',
              ),
            ],
            if (_dueQuizEvents.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionTitle('授業中クイズ'),
              const SizedBox(height: 8),
              for (final event in _dueQuizEvents) ...[
                _QuizCard(
                  event: event,
                  selectedChoiceIndex: _selectedChoices[event.id],
                  answerResult: _answerResults[event.id],
                  alreadyAnswered: _answeredQuizEventIds.contains(event.id),
                  onChoiceChanged: (choiceIndex) {
                    setState(() {
                      _selectedChoices[event.id] = choiceIndex;
                      _message = null;
                    });
                  },
                  onSubmit: () => _submitAnswer(event),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (statusMessage != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(statusMessage),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle('学習メモ'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLessonNotesOpen = !_isLessonNotesOpen;
                });
              },
              icon: Icon(
                _isLessonNotesOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.note_alt_outlined,
              ),
              label: Text(_isLessonNotesOpen ? 'レッスンメモを閉じる' : 'レッスンメモを開く'),
            ),
            if (_isLessonNotesOpen) ...[
              const SizedBox(height: 12),
              LessonNotesPanel(
                course: course,
                lesson: lesson,
                lessonNumber: lessonNumber,
                isEmbedded: true,
                isTeacherPreview: _isTeacherPreview,
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle('質問コメント'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLessonQuestionsOpen = !_isLessonQuestionsOpen;
                });
              },
              icon: Icon(
                _isLessonQuestionsOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.question_answer_outlined,
              ),
              label: Text(
                _isLessonQuestionsOpen ? '質問コメント欄を閉じる' : '質問コメント欄を開く',
              ),
            ),
            if (_isLessonQuestionsOpen) ...[
              const SizedBox(height: 12),
              LessonQuestionsPanel(
                course: course,
                lesson: lesson,
                lessonNumber: lessonNumber,
                isEmbedded: true,
                isTeacherPreview: _isTeacherPreview,
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle('この画面の機能'),
            const SizedBox(height: 8),
            _BulletText('メディアファイルの再生'),
            const _BulletText('再生位置の保存'),
            const _BulletText('視聴完了チェック'),
            const _BulletText('コメント・質問欄'),
          ],
        ),
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.event,
    required this.selectedChoiceIndex,
    required this.answerResult,
    required this.alreadyAnswered,
    required this.onChoiceChanged,
    required this.onSubmit,
  });

  final LessonEvent event;
  final int? selectedChoiceIndex;
  final bool? answerResult;
  final bool alreadyAnswered;
  final ValueChanged<int> onChoiceChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final quiz = event.quiz!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${event.timestampSec}秒のクイズ'),
            const SizedBox(height: 8),
            Text(
              quiz.question,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final entry in quiz.choices.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selectedChoiceIndex == entry.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(entry.$2),
                onTap: () => onChoiceChanged(entry.$1),
              ),
            if (alreadyAnswered)
              const Text('この周では回答済みです。')
            else
              FilledButton(onPressed: onSubmit, child: const Text('回答する')),
            if (answerResult != null) ...[
              const SizedBox(height: 8),
              Text(answerResult! ? '結果: 正解' : '結果: 不正解'),
              if (quiz.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('解説: ${quiz.explanation}'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
