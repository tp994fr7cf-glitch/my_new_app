import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';

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
    this.onQuizAnswerSaveOverride,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final QuizAnswerSaveOverride? onQuizAnswerSaveOverride;

  @override
  State<VideoLessonPage> createState() => _VideoLessonPageState();
}

class _VideoLessonPageState extends State<VideoLessonPage>
    with WidgetsBindingObserver {
  static const int _developmentPlaybackDurationSec = 90;
  static const double _completionRate = 0.92;
  static const Duration _resumeWindow = Duration(hours: 24);

  int _currentPositionSec = 0;
  int _studySeconds = 0;
  int _watchSeconds = 0;
  int _cycleNumber = 1;
  int _cycleMaxWatchedPositionSec = 0;
  bool _isPlaying = false;
  bool _isPreparingSession = false;
  bool _sessionCompleted = false;
  bool _hasPlaybackStarted = false;
  bool _pendingCompletion = false;
  Timer? _playbackTimer;
  Timer? _studyTimer;
  String? _sessionId;
  String? _segmentId;
  final Map<String, int> _selectedChoices = {};
  final Map<String, bool> _answerResults = {};
  final Set<String> _answeredQuizEventIds = {};
  String? _message;

  Course get course => widget.course;
  CourseLesson get lesson => widget.lesson;
  int get lessonNumber => widget.lessonNumber;

  bool get _isAudioLesson => lesson.mediaType == 'audio';
  int get _totalDurationSec => _developmentPlaybackDurationSec;
  int get _completionThresholdSec =>
      (_totalDurationSec * _completionRate).round();
  bool get _isAtEnd => _currentPositionSec >= _totalDurationSec;
  bool get _hasActiveSession => _sessionId != null && !_sessionCompleted;
  String get _taskKey => '${_courseId()}-$lessonNumber-$_cycleNumber';
  IconData get _playButtonIcon {
    if (_isPlaying) {
      return Icons.pause;
    }
    if (_isAtEnd) {
      return Icons.replay;
    }
    return Icons.play_arrow;
  }

  String get _playButtonLabel {
    if (_isPreparingSession) {
      return '準備中';
    }
    if (_isPlaying) {
      return '一時停止';
    }
    if (_sessionCompleted || _isAtEnd) {
      return 'もう一度再生';
    }
    return '再生';
  }

  List<LessonEvent> get _dueQuizEvents {
    if (!_hasActiveSession) {
      return const [];
    }

    return course.lessonEvents
        .where((event) => event.lessonNumber == lessonNumber)
        .where((event) => event.isQuiz)
        .where((event) => event.timestampSec <= _currentPositionSec)
        .toList()
      ..sort((a, b) => a.timestampSec.compareTo(b.timestampSec));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resumeLearningTimeOnOpen());
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _studyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_pendingCompletion && !_sessionCompleted) {
      unawaited(_completeCurrentSegment(updateUi: false));
    } else {
      unawaited(_persistSessionProgress());
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
      if (_pendingCompletion && !_sessionCompleted) {
        unawaited(_completeCurrentSegment());
      } else {
        unawaited(_persistSessionProgress());
      }
      return;
    }

    if (state == AppLifecycleState.resumed && _hasActiveSession) {
      _startStudyTimer();
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      _pausePlayback();
      return;
    }

    if (_sessionCompleted || _isAtEnd) {
      setState(() {
        _currentPositionSec = 0;
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
        _message = null;
      });
    }

    final prepared = await _ensureSession();
    if (!prepared || !mounted) {
      return;
    }

    setState(() {
      _hasPlaybackStarted = true;
      _isPlaying = true;
      _message = null;
    });
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _playbackTimer?.cancel();
        return;
      }

      var shouldPersistPending = false;
      setState(() {
        if (_currentPositionSec < _totalDurationSec) {
          _currentPositionSec += 1;
        }
        _addWatchProgress(_currentPositionSec);
        if (_currentPositionSec >= _completionThresholdSec &&
            !_pendingCompletion) {
          _setCompletionPendingState();
          shouldPersistPending = true;
        }
      });
      if (shouldPersistPending) {
        unawaited(_persistSessionProgress());
      }
    });
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  Future<void> _advanceTime() async {
    final prepared = await _ensureSession();
    if (!prepared || !mounted) {
      return;
    }

    setState(() {
      _hasPlaybackStarted = true;
      _currentPositionSec = (_currentPositionSec + 30)
          .clamp(0, _totalDurationSec)
          .toInt();
      _addWatchProgress(_currentPositionSec);
      _message = null;
    });
    if (_currentPositionSec >= _completionThresholdSec && !_pendingCompletion) {
      await _markCompletionPending();
    }
  }

  String _courseId() {
    return course.id ?? course.title.replaceAll('/', '_');
  }

  Future<bool> _ensureSession() async {
    if (_hasActiveSession && _segmentId != null) {
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

      final session = await _loadOrCreateCycleSession(user);
      await _loadOrCreateSegment(user, session);
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

  void _startLocalSession() {
    _sessionId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    _segmentId = 'local-segment-${DateTime.now().microsecondsSinceEpoch}';
    _cycleNumber = _sessionCompleted ? _cycleNumber + 1 : _cycleNumber;
    _sessionCompleted = false;
    _studySeconds = 0;
    _watchSeconds = 0;
    _cycleMaxWatchedPositionSec = 0;
    _hasPlaybackStarted = true;
    _pendingCompletion = false;
    _answeredQuizEventIds.clear();
    _startStudyTimer();
  }

  void _loadSession(String sessionId, Map<String, dynamic> data) {
    _sessionId = sessionId;
    _cycleNumber = (data['cycleNumber'] as num?)?.toInt() ?? 1;
    _sessionCompleted =
        data['status'] == 'completed' || data['cycleCompleted'] == true;
    _cycleMaxWatchedPositionSec =
        (data['maxWatchedPositionSec'] as num?)?.toInt() ??
        (data['maxPositionSec'] as num?)?.toInt() ??
        0;
    _currentPositionSec = _cycleMaxWatchedPositionSec;
    _hasPlaybackStarted = data['hasPlaybackStarted'] == true;
    _pendingCompletion = data['pendingCompletion'] == true;
    final answered = data['answeredQuizEventIds'];
    _answeredQuizEventIds
      ..clear()
      ..addAll(answered is List ? answered.whereType<String>() : const []);
  }

  Future<void> _resumeLearningTimeOnOpen() async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final session = await _latestCycleSession(user);
      if (session == null) {
        return;
      }

      final data = session.data();
      final isCompleted =
          data['status'] == 'completed' || data['cycleCompleted'] == true;
      final hasPlaybackStarted = data['hasPlaybackStarted'] == true;
      if (isCompleted || !hasPlaybackStarted) {
        return;
      }

      _loadSession(session.id, data);
      await _loadOrCreateSegment(user, session);
      _startStudyTimer();
    } catch (_) {
      // Opening the page should still work even if record resume fails.
    }
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

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _latestOverallSegment(
    User user,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonViewSegments')
        .orderBy('lastActivityAt', descending: true)
        .limit(1)
        .get();

    return snapshot.docs.isEmpty ? null : snapshot.docs.first;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadOrCreateCycleSession(
    User user,
  ) async {
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
        _loadSession(latest.id, latestData);
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
    });

    final created = await newSessionRef.get();
    _loadSession(created.id, created.data()!);
    return created;
  }

  Future<void> _loadOrCreateSegment(
    User user,
    DocumentSnapshot<Map<String, dynamic>> session,
  ) async {
    final latestOverall = await _latestOverallSegment(user);
    final now = DateTime.now();
    final segmentsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonViewSegments');

    if (latestOverall != null) {
      final latestData = latestOverall.data();
      final lastActivityAt = latestData['lastActivityAt'];
      final lastActivityDate = lastActivityAt is Timestamp
          ? lastActivityAt.toDate()
          : null;
      final canResumeSegment =
          latestData['sessionId'] == session.id &&
          latestData['status'] == 'inProgress' &&
          latestData['isDeleted'] != true &&
          lastActivityDate != null &&
          now.difference(lastActivityDate) < _resumeWindow;

      if (canResumeSegment) {
        _segmentId = latestOverall.id;
        _studySeconds = (latestData['studySeconds'] as num?)?.toInt() ?? 0;
        _watchSeconds = (latestData['watchSeconds'] as num?)?.toInt() ?? 0;
        return;
      }
    }

    final newSegmentRef = segmentsRef.doc();
    final startedAt = FieldValue.serverTimestamp();
    await newSegmentRef.set({
      'userId': user.uid,
      'sessionId': session.id,
      'courseId': _courseId(),
      'courseTitle': course.title,
      'lessonNumber': lessonNumber,
      'lessonTitle': lesson.title,
      'cycleNumber': _cycleNumber,
      'taskKey': _taskKey,
      'status': 'inProgress',
      'startedAt': startedAt,
      'lastActivityAt': startedAt,
      'studySeconds': 0,
      'watchSeconds': 0,
      'startPositionSec': _cycleMaxWatchedPositionSec,
      'endPositionSec': _cycleMaxWatchedPositionSec,
      'isDeleted': false,
    });
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

  void _addWatchProgress(int currentPositionSec) {
    if (currentPositionSec <= _cycleMaxWatchedPositionSec) {
      return;
    }

    final newWatchSeconds = currentPositionSec - _cycleMaxWatchedPositionSec;
    _watchSeconds += newWatchSeconds;
    _cycleMaxWatchedPositionSec = currentPositionSec;
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

    await batch.commit();
  }

  Future<void> _markCompletionPending() async {
    if (_pendingCompletion || _sessionCompleted) {
      return;
    }

    setState(() {
      _setCompletionPendingState();
    });

    await _persistSessionProgress();
  }

  void _setCompletionPendingState() {
    _playbackTimer?.cancel();
    _isPlaying = false;
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

    await batch.commit();
  }

  Future<void> _completeManually() async {
    final prepared = await _ensureSession();
    if (!prepared || !mounted) {
      return;
    }
    await _completeCurrentSegment();
  }

  Future<void> _submitAnswer(LessonEvent event) async {
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

    final courseId = course.id ?? course.title.replaceAll('/', '_');
    final sessionId = _sessionId;
    final cycleQuizKey = sessionId == null
        ? '${courseId}_${lessonNumber}_${_cycleNumber}_${event.id}'
        : '${sessionId}_${event.id}';
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

    return Scaffold(
      appBar: AppBar(title: Text(_isAudioLesson ? '音声授業' : '動画視聴')),
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
                    Icon(
                      _isAudioLesson ? Icons.headphones : Icons.smart_display,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(_isAudioLesson ? '音声プレイヤー仮UI' : '動画プレイヤー仮UI'),
                    const SizedBox(height: 4),
                    Text(
                      _isAudioLesson
                          ? '実際の音声再生機能は後で追加します。'
                          : '実際の動画再生機能は後で追加します。',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${_formatTime(_currentPositionSec)} / ${_formatTime(_totalDurationSec)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: LinearProgressIndicator(
                        value: _totalDurationSec == 0
                            ? 0
                            : _currentPositionSec / _totalDurationSec,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isPreparingSession
                          ? null
                          : () {
                              unawaited(_togglePlayback());
                            },
                      icon: Icon(_playButtonIcon),
                      label: Text(_playButtonLabel),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(course.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'レッスン$lessonNumber: ${lesson.title}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('再生時間: ${lesson.duration}'),
            const SizedBox(height: 8),
            Text('授業形式: ${_isAudioLesson ? '音声のみ' : '動画'}'),
            const SizedBox(height: 8),
            Text('仮再生時間: ${_formatTime(_totalDurationSec)}'),
            const SizedBox(height: 8),
            Text('現在位置: ${_formatTime(_currentPositionSec)}'),
            const SizedBox(height: 8),
            Text('現在の周回: $_cycleNumber周目'),
            const SizedBox(height: 8),
            Text('学習時間: $_studySeconds秒'),
            const SizedBox(height: 8),
            Text('視聴時間: $_watchSeconds秒'),
            const SizedBox(height: 8),
            Text('視聴終了判定: $_completionThresholdSec秒到達'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                unawaited(_advanceTime());
              },
              icon: const Icon(Icons.forward_30),
              label: const Text('30秒進める（開発用）'),
            ),
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
            if (lesson.mediaUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('仮URL: ${lesson.mediaUrl}'),
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
            const TextField(
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'このレッスンで気づいたことをメモできます。保存機能は後で追加します。',
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('この画面に後で追加する機能'),
            const SizedBox(height: 8),
            _BulletText(_isAudioLesson ? '実際の音声プレイヤー' : '実際の動画プレイヤー'),
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
