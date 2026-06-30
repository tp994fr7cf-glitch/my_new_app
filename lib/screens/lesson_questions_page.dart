import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/comment_identity.dart';
import '../models/course.dart';
import '../models/course_participant_identity.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';
import '../models/public_user_profile.dart';
import '../services/course_identity_service.dart';
import '../services/lesson_interaction_service.dart';
import '../utils/firestore_parsing.dart';
import 'lesson_notes_page.dart';
import 'public_note_edit_history_sheet.dart';
import 'public_user_profile_page.dart';
import 'shared/lesson_note_preview_body.dart';

class LessonQuestionsActiveRoleState {
  const LessonQuestionsActiveRoleState({
    required this.isResolved,
    required this.isTeacher,
  });

  final bool isResolved;
  final bool isTeacher;
}

class LessonQuestionsPanel extends StatefulWidget {
  const LessonQuestionsPanel({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.questionsStream,
    this.publicQuestionsStream,
    this.answersStream,
    this.quotableNotesStream,
    this.isEmbedded = false,
    this.isTeacherPreview = false,
    this.initialEditingQuestion,
    this.initialSelectedQuestion,
    this.initialQuotedNote,
    this.initialHighlightedAnswerId,
    this.teacherHiddenOwnQuestionIdsStream,
    this.activeRoleStateStream,
    this.publicRestrictionModeStream,
    this.questionAuthorRestrictionModeStreamBuilder,
    this.currentUserIdOverride,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonQuestion>>? questionsStream;
  final Stream<List<LessonQuestion>>? publicQuestionsStream;
  final Stream<List<LessonQuestionAnswer>>? answersStream;
  final Stream<List<LessonNote>>? quotableNotesStream;
  final bool isEmbedded;
  final bool isTeacherPreview;
  final LessonQuestion? initialEditingQuestion;
  final LessonQuestion? initialSelectedQuestion;
  final LessonNote? initialQuotedNote;
  final String? initialHighlightedAnswerId;
  final Stream<Set<String>>? teacherHiddenOwnQuestionIdsStream;
  final Stream<LessonQuestionsActiveRoleState>? activeRoleStateStream;
  final Stream<String>? publicRestrictionModeStream;
  final Stream<String> Function(LessonQuestion question)?
  questionAuthorRestrictionModeStreamBuilder;
  final String? currentUserIdOverride;

  @override
  State<LessonQuestionsPanel> createState() => _LessonQuestionsPanelState();
}

enum _MyCommentTab { questions, answers }

class _LessonQuestionsPanelState extends State<LessonQuestionsPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _myQuestionsScrollController = ScrollController();
  final ScrollController _myAnswersScrollController = ScrollController();
  final ScrollController _publicQuestionsScrollController = ScrollController();
  final ScrollController _teacherPreviewPublicScrollController =
      ScrollController();
  late final TabController _questionTabController;
  ScrollController? _restoreScrollController;
  double _restoreScrollOffset = 0;
  int _restoreTabIndex = 0;
  _MyCommentTab _restoreMyCommentTab = _MyCommentTab.questions;
  bool _restorePending = false;
  DateTime? _restoreStartedAt;
  int _restoreGeneration = 0;
  bool _restoreApplyingJump = false;
  bool _restoreCancelledByUser = false;
  bool _restorePostCorrectionPending = false;
  List<LessonQuestion> _lastMyQuestions = const [];
  List<LessonQuestionAnswer> _lastMyAnswers = const [];
  Map<String, LessonQuestion> _lastMyAnswerQuestions =
      const <String, LessonQuestion>{};
  Map<String, LessonQuestionAnswer> _lastMyAnswerParentAnswers =
      const <String, LessonQuestionAnswer>{};
  List<LessonQuestion> _lastPublicQuestions = const [];
  List<LessonQuestion> _lastTeacherPreviewPublicQuestions = const [];
  List<LessonQuestionAnswer> _lastPublicAnswers = const [];
  List<LessonQuestionAnswer> _lastTeacherPreviewAnswers = const [];
  List<LessonNote> _lastQuotablePublicNotes = const [];
  List<LessonNote> _lastQuotableOwnNotes = const [];
  List<LessonNote> _lastQuotableOwnLegacyNotes = const [];
  Set<String> _lastTeacherHiddenOwnQuestionIds = const <String>{};
  late Stream<List<LessonNote>> _sharedQuotableNotesStream;
  Stream<List<LessonQuestion>>? _providedQuestionsSource;
  Stream<List<LessonQuestion>>? _providedQuestionsBroadcast;
  Stream<List<LessonQuestion>>? _providedPublicQuestionsSource;
  Stream<List<LessonQuestion>>? _providedPublicQuestionsBroadcast;
  Stream<List<LessonQuestionAnswer>>? _providedAnswersSource;
  Stream<List<LessonQuestionAnswer>>? _providedAnswersBroadcast;
  Stream<List<LessonQuestion>>? _cachedMyQuestionsStream;
  Object? _cachedMyQuestionsStreamKey;
  Stream<List<LessonQuestionAnswer>>? _cachedMyAnswersStream;
  Object? _cachedMyAnswersStreamKey;
  Stream<Map<String, LessonQuestion>>? _cachedMyAnswerQuestionsStream;
  Object? _cachedMyAnswerQuestionsStreamKey;
  Stream<Map<String, LessonQuestionAnswer>>? _cachedMyAnswerParentsStream;
  Object? _cachedMyAnswerParentsStreamKey;
  Stream<List<LessonQuestion>>? _cachedPublicQuestionsStream;
  Object? _cachedPublicQuestionsStreamKey;
  Stream<Set<String>>? _cachedTeacherHiddenOwnQuestionIdsStream;
  Object? _cachedTeacherHiddenOwnQuestionIdsStreamKey;
  Stream<List<LessonQuestion>>? _cachedTeacherPreviewPublicQuestionsStream;
  Object? _cachedTeacherPreviewPublicQuestionsStreamKey;
  Stream<String>? _cachedLearnerRestrictionModeStream;
  Object? _cachedLearnerRestrictionModeStreamKey;
  Stream<bool>? _cachedQuestionPublicPlatformEnabledStream;
  String? _cachedQuestionPublicPlatformEnabledStreamKey;
  LessonQuestionSort _myQuestionsSort = LessonQuestionSort.newest;
  LessonQuestionSort _myAnswersSort = LessonQuestionSort.newest;
  LessonQuestionSort _publicQuestionsSort = LessonQuestionSort.newest;
  _MyCommentTab _myCommentTab = _MyCommentTab.questions;
  String _query = '';
  String? _message;
  LessonQuestion? _editingQuestion;
  LessonQuestion? _selectedQuestion;
  String? _currentHighlightedAnswerId;
  StreamSubscription<dynamic>? _profileSubscription;
  bool _activeRoleIsTeacher = false;
  bool _activeRoleResolved = false;
  bool _openingAnswerDetailFromList = false;
  final LessonInteractionService _lessonInteractionService =
      const LessonInteractionService();
  final CourseIdentityService _courseIdentityService =
      const CourseIdentityService();

  String get _courseId => widget.course.storageId;

  String? get _currentUserId {
    final override = (widget.currentUserIdOverride ?? '').trim();
    if (override.isNotEmpty) {
      return override;
    }
    return Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
  }

  bool get _isCurrentUserTeacher =>
      _activeRoleIsTeacher &&
      _currentUserId != null &&
      widget.course.instructorId == _currentUserId;

  bool get _canAccessTeacherOnlyQuotablePublicNotes =>
      widget.isTeacherPreview || _isCurrentUserTeacher;

  bool _canAccessTeacherOnlyQuotablePublicNotesForRole({
    required bool activeRoleIsTeacher,
  }) {
    final currentUserId = _currentUserId;
    final isCurrentUserTeacher =
        activeRoleIsTeacher &&
        currentUserId != null &&
        widget.course.instructorId == currentUserId;
    return widget.isTeacherPreview || isCurrentUserTeacher;
  }

  Stream<String> _learnerRestrictionModeStream() {
    final cacheKey = Object.hash(
      widget.publicRestrictionModeStream,
      _questionStreamScopeKey,
      'learnerRestrictionMode',
    );
    if (_cachedLearnerRestrictionModeStream != null &&
        _cachedLearnerRestrictionModeStreamKey == cacheKey) {
      return _cachedLearnerRestrictionModeStream!;
    }
    final provided = widget.publicRestrictionModeStream;
    late final Stream<String> stream;
    if (provided != null) {
      stream = provided.map(
        _lessonInteractionService.normalizeLearnerRestrictionMode,
      );
    } else {
      final userId = _currentUserId;
      if (widget.isTeacherPreview ||
          _isCurrentUserTeacher ||
          userId == null ||
          userId.isEmpty) {
        stream = Stream.value(
          LessonInteractionService.learnerRestrictionModeNone,
        );
      } else {
        stream = _lessonInteractionService.learnerRestrictionModeStream(
          courseId: _courseId,
          lessonNumber: widget.lessonNumber,
          learnerId: userId,
        );
      }
    }
    final broadcast = stream.asBroadcastStream();
    _cachedLearnerRestrictionModeStream = broadcast;
    _cachedLearnerRestrictionModeStreamKey = cacheKey;
    return broadcast;
  }

  Future<String> _currentLearnerRestrictionMode() async {
    final userId = _currentUserId;
    if (widget.isTeacherPreview ||
        _isCurrentUserTeacher ||
        userId == null ||
        userId.isEmpty) {
      return LessonInteractionService.learnerRestrictionModeNone;
    }
    return _lessonInteractionService.learnerRestrictionMode(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      learnerId: userId,
    );
  }

  Stream<String> _questionAuthorRestrictionModeStream(LessonQuestion question) {
    final providedBuilder = widget.questionAuthorRestrictionModeStreamBuilder;
    if (providedBuilder != null) {
      return providedBuilder(
        question,
      ).map(_lessonInteractionService.normalizeLearnerRestrictionMode);
    }
    final safeAuthorId = question.authorId.trim();
    if (widget.isTeacherPreview ||
        _isCurrentUserTeacher ||
        !question.isPubliclyVisible ||
        question.authorRole == 'teacher' ||
        safeAuthorId.isEmpty ||
        Firebase.apps.isEmpty) {
      return Stream.value(LessonInteractionService.learnerRestrictionModeNone);
    }
    return _lessonInteractionService.learnerRestrictionModeStream(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      learnerId: safeAuthorId,
    );
  }

  Future<String> _currentQuestionAuthorRestrictionMode(
    LessonQuestion question,
  ) async {
    final providedBuilder = widget.questionAuthorRestrictionModeStreamBuilder;
    if (providedBuilder != null) {
      try {
        return _lessonInteractionService.normalizeLearnerRestrictionMode(
          await providedBuilder(question).first,
        );
      } catch (_) {
        return LessonInteractionService.learnerRestrictionModeNone;
      }
    }
    final safeAuthorId = question.authorId.trim();
    if (widget.isTeacherPreview ||
        _isCurrentUserTeacher ||
        !question.isPubliclyVisible ||
        question.authorRole == 'teacher' ||
        safeAuthorId.isEmpty ||
        Firebase.apps.isEmpty) {
      return LessonInteractionService.learnerRestrictionModeNone;
    }
    return _lessonInteractionService.learnerRestrictionMode(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      learnerId: safeAuthorId,
    );
  }

  bool _isAnswerBlockedByQuestionAuthorRestriction({
    required LessonQuestion question,
    required String questionAuthorRestrictionMode,
    required String? actingUserId,
    required bool isActingUserTeacher,
  }) {
    return _lessonInteractionService.blocksOthersFromAnsweringPublicQuestion(
      questionAuthorId: question.authorId,
      questionAuthorRole: question.authorRole,
      actingUserId: actingUserId,
      questionAuthorRestrictionMode: questionAuthorRestrictionMode,
      questionIsPubliclyVisible: question.isPubliclyVisible,
      isActingUserTeacher: isActingUserTeacher,
      isTeacherPreview: widget.isTeacherPreview,
    );
  }

  @override
  void initState() {
    super.initState();
    _questionTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isTeacherPreview ? 1 : 0,
    );
    _editingQuestion =
        widget.initialEditingQuestion ??
        _initialQuestionDraftForQuotedNote(widget.initialQuotedNote);
    _selectedQuestion = widget.initialSelectedQuestion;
    _currentHighlightedAnswerId = _normalizedAnswerId(
      widget.initialHighlightedAnswerId,
    );
    _refreshSharedQuotableNotesStream(resetCache: true);
    _listenToActiveRole();
  }

  @override
  void didUpdateWidget(covariant LessonQuestionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeRoleStateStream != oldWidget.activeRoleStateStream) {
      _listenToActiveRole();
    }
    final shouldRefreshQuotableStream =
        widget.quotableNotesStream != oldWidget.quotableNotesStream ||
        widget.course.storageId != oldWidget.course.storageId ||
        widget.lessonNumber != oldWidget.lessonNumber ||
        widget.isTeacherPreview != oldWidget.isTeacherPreview;
    if (!shouldRefreshQuotableStream) {
      if (widget.initialHighlightedAnswerId !=
              oldWidget.initialHighlightedAnswerId &&
          _selectedQuestion == null) {
        _currentHighlightedAnswerId = _normalizedAnswerId(
          widget.initialHighlightedAnswerId,
        );
      }
      return;
    }
    _refreshSharedQuotableNotesStream(resetCache: true);
  }

  void _refreshSharedQuotableNotesStream({required bool resetCache}) {
    if (resetCache) {
      _lastQuotablePublicNotes = const [];
      _lastQuotableOwnNotes = const [];
      _lastQuotableOwnLegacyNotes = const [];
    }
    final source = _quotableNotesStream();
    _sharedQuotableNotesStream = source.isBroadcast
        ? source
        : source.asBroadcastStream();
  }

  void _applyActiveRoleState({
    required bool isResolved,
    required bool isTeacher,
  }) {
    if (!mounted) {
      return;
    }
    final previousCanAccessTeacherOnlyPublicNotes =
        _canAccessTeacherOnlyQuotablePublicNotesForRole(
          activeRoleIsTeacher: _activeRoleIsTeacher,
        );
    final nextRoleIsTeacher = isResolved && isTeacher;
    final nextCanAccessTeacherOnlyPublicNotes =
        _canAccessTeacherOnlyQuotablePublicNotesForRole(
          activeRoleIsTeacher: nextRoleIsTeacher,
        );
    final canAccessTeacherOnlyPublicNotesChanged =
        previousCanAccessTeacherOnlyPublicNotes !=
        nextCanAccessTeacherOnlyPublicNotes;
    final stateChanged =
        _activeRoleResolved != isResolved ||
        _activeRoleIsTeacher != nextRoleIsTeacher;
    if (!stateChanged) {
      return;
    }
    setState(() {
      _activeRoleResolved = isResolved;
      _activeRoleIsTeacher = nextRoleIsTeacher;
      if (canAccessTeacherOnlyPublicNotesChanged) {
        _refreshSharedQuotableNotesStream(resetCache: true);
      }
    });
  }

  void _listenToActiveRole() {
    _profileSubscription?.cancel();
    final roleStateStream = widget.activeRoleStateStream;
    if (roleStateStream != null) {
      _profileSubscription = roleStateStream.listen((state) {
        _applyActiveRoleState(
          isResolved: state.isResolved,
          isTeacher: state.isTeacher,
        );
      });
      return;
    }
    if (Firebase.apps.isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    _profileSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          final activeRole = snapshot.data()?['activeRole'];
          if (!_activeRoleResolved && snapshot.metadata.isFromCache) {
            return;
          }
          _applyActiveRoleState(
            isResolved: true,
            isTeacher: activeRole == 'teacher',
          );
        });
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _restoreScrollController?.removeListener(
      _handleRestoreScrollControllerChange,
    );
    _questionTabController.dispose();
    _queryController.dispose();
    _myQuestionsScrollController.dispose();
    _myAnswersScrollController.dispose();
    _publicQuestionsScrollController.dispose();
    _teacherPreviewPublicScrollController.dispose();
    super.dispose();
  }

  String? _normalizedAnswerId(String? answerId) {
    final normalized = (answerId ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Stream<List<LessonQuestion>> _asBroadcastQuestionsStream(
    Stream<List<LessonQuestion>> source, {
    required bool isPublic,
  }) {
    if (isPublic) {
      if (!identical(source, _providedPublicQuestionsSource)) {
        _providedPublicQuestionsSource = source;
        _providedPublicQuestionsBroadcast = source.asBroadcastStream();
      }
      return _providedPublicQuestionsBroadcast!;
    }
    if (!identical(source, _providedQuestionsSource)) {
      _providedQuestionsSource = source;
      _providedQuestionsBroadcast = source.asBroadcastStream();
    }
    return _providedQuestionsBroadcast!;
  }

  Stream<List<LessonQuestionAnswer>> _asBroadcastAnswersStream(
    Stream<List<LessonQuestionAnswer>> source,
  ) {
    if (!identical(source, _providedAnswersSource)) {
      _providedAnswersSource = source;
      _providedAnswersBroadcast = source.asBroadcastStream();
    }
    return _providedAnswersBroadcast!;
  }

  String get _questionStreamScopeKey =>
      '${widget.course.storageId}:${widget.lessonNumber}:'
      '$widget.isTeacherPreview:$_activeRoleResolved:$_activeRoleIsTeacher:${_currentUserId ?? ''}';

  void _setRestoreScrollController(ScrollController? controller) {
    if (identical(_restoreScrollController, controller)) {
      return;
    }
    _restoreScrollController?.removeListener(
      _handleRestoreScrollControllerChange,
    );
    _restoreScrollController = controller;
    _restoreScrollController?.addListener(_handleRestoreScrollControllerChange);
  }

  void _handleRestoreScrollControllerChange() {
    if (_restoreApplyingJump) {
      return;
    }
    final controller = _restoreScrollController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    if (controller.position.userScrollDirection != ScrollDirection.idle) {
      _restoreCancelledByUser = true;
      _restorePostCorrectionPending = false;
    }
  }

  void _openQuestionDetail(
    LessonQuestion question,
    ScrollController sourceController, {
    String? highlightedAnswerId,
  }) {
    _restoreTabIndex = _questionTabController.index;
    _restoreMyCommentTab = _myCommentTab;
    _setRestoreScrollController(sourceController);
    _restoreScrollOffset = sourceController.hasClients
        ? sourceController.offset
        : 0;
    _restorePending = _restoreScrollOffset > 0;
    _restoreStartedAt = null;
    _restoreGeneration += 1;
    _restoreCancelledByUser = false;
    _restorePostCorrectionPending = false;
    setState(() {
      _lastPublicAnswers = const [];
      _lastTeacherPreviewAnswers = const [];
      _selectedQuestion = question;
      _currentHighlightedAnswerId = _normalizedAnswerId(highlightedAnswerId);
    });
  }

  void _backToQuestionList() {
    if (_questionTabController.index != _restoreTabIndex) {
      _questionTabController.index = _restoreTabIndex;
    }
    setState(() {
      _selectedQuestion = null;
      _currentHighlightedAnswerId = null;
      _myCommentTab = _restoreMyCommentTab;
    });
    _restoreCancelledByUser = false;
    if (_restorePending) {
      _restoreScrollWhenReady();
    }
  }

  void _restoreScrollWhenReady() {
    final controller = _restoreScrollController;
    if (controller == null) {
      _restorePending = false;
      return;
    }
    _restoreStartedAt ??= DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_restorePending) {
        _restorePending = false;
        return;
      }
      if (_restoreCancelledByUser) {
        _restorePending = false;
        return;
      }
      final currentController = _restoreScrollController;
      if (currentController == null || !currentController.hasClients) {
        _scheduleRestoreRetry();
        return;
      }
      final max = currentController.position.maxScrollExtent;
      if (max <= 0) {
        _scheduleRestoreRetry();
        return;
      }
      final target = _restoreScrollOffset.clamp(0, max).toDouble();
      final closeEnough = (currentController.offset - target).abs() < 1;
      if (closeEnough) {
        _restorePending = false;
        return;
      }
      _restoreApplyingJump = true;
      currentController.jumpTo(target);
      _restoreApplyingJump = false;
      _restorePending = false;
      _schedulePostRestoreCorrection(
        targetOffset: target,
        generation: _restoreGeneration,
      );
    });
  }

  void _scheduleRestoreRetry() {
    if (!_restorePending) {
      _restorePending = false;
      return;
    }
    final startedAt = _restoreStartedAt;
    if (startedAt == null) {
      _restoreStartedAt = DateTime.now();
    } else if (DateTime.now().difference(startedAt) >
        const Duration(seconds: 3)) {
      _restorePending = false;
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (!mounted || !_restorePending) {
        return;
      }
      _restoreScrollWhenReady();
    });
  }

  void _schedulePostRestoreCorrection({
    required double targetOffset,
    required int generation,
  }) {
    _restorePostCorrectionPending = true;
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (!mounted || !_restorePostCorrectionPending) {
        return;
      }
      if (generation != _restoreGeneration || _restoreCancelledByUser) {
        _restorePostCorrectionPending = false;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _restoreGeneration ||
            _restoreCancelledByUser) {
          _restorePostCorrectionPending = false;
          return;
        }
        final controller = _restoreScrollController;
        if (controller == null || !controller.hasClients) {
          _restorePostCorrectionPending = false;
          return;
        }
        final max = controller.position.maxScrollExtent;
        if (max <= 0) {
          _restorePostCorrectionPending = false;
          return;
        }
        final correctedTarget = targetOffset.clamp(0, max).toDouble();
        final closeEnough = (controller.offset - correctedTarget).abs() < 1;
        if (!closeEnough) {
          _restoreApplyingJump = true;
          controller.jumpTo(correctedTarget);
          _restoreApplyingJump = false;
        }
        _restorePostCorrectionPending = false;
      });
    });
  }

  Stream<List<LessonQuestion>> _questionsStream() {
    final cacheKey = Object.hash(
      widget.questionsStream,
      _questionStreamScopeKey,
      _myQuestionsSort,
    );
    if (_cachedMyQuestionsStream != null &&
        _cachedMyQuestionsStreamKey == cacheKey) {
      return _cachedMyQuestionsStream!;
    }
    final provided = widget.questionsStream;
    late final Stream<List<LessonQuestion>> stream;
    if (provided != null) {
      stream = _asBroadcastQuestionsStream(provided, isPublic: false).map(
        (questions) => sortLessonQuestions(
          questions
              .where((question) => !question.isDeleted)
              .where(_matchesActiveRole)
              .toList(),
          _myQuestionsSort,
        ),
      );
    } else if (Firebase.apps.isEmpty) {
      stream = Stream.value(const []);
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        stream = Stream.value(const []);
      } else {
        stream = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestions')
            .where('courseId', isEqualTo: _courseId)
            .where('lessonNumber', isEqualTo: widget.lessonNumber)
            .snapshots()
            .map((snapshot) {
              return sortLessonQuestions(
                snapshot.docs
                    .map(LessonQuestion.fromFirestore)
                    .where((question) => !question.isDeleted)
                    .where(_matchesActiveRole)
                    .toList(),
                _myQuestionsSort,
              );
            });
      }
    }
    final tracked = stream.map((questions) {
      _lastMyQuestions = questions;
      return questions;
    });
    final broadcast = tracked.asBroadcastStream();
    _cachedMyQuestionsStream = broadcast;
    _cachedMyQuestionsStreamKey = cacheKey;
    return broadcast;
  }

  String get _activeCommentRole => widget.isTeacherPreview
      ? 'teacher'
      : !_activeRoleResolved
      ? ''
      : (_activeRoleIsTeacher ? 'teacher' : 'student');

  bool _matchesActiveRole(LessonQuestion question) {
    final activeRole = _activeCommentRole;
    if (activeRole.isEmpty) {
      return true;
    }
    return question.authorRole == activeRole;
  }

  bool _matchesActiveAnswerRole(LessonQuestionAnswer answer) {
    final activeRole = _activeCommentRole;
    if (activeRole.isEmpty) {
      return true;
    }
    return answer.authorRole == activeRole;
  }

  Stream<List<LessonQuestionAnswer>> _myAnswersStream() {
    final cacheKey = Object.hash(
      widget.answersStream,
      _questionStreamScopeKey,
      _myAnswersSort,
    );
    if (_cachedMyAnswersStream != null &&
        _cachedMyAnswersStreamKey == cacheKey) {
      return _cachedMyAnswersStream!;
    }
    final provided = widget.answersStream;
    late final Stream<List<LessonQuestionAnswer>> stream;
    if (provided != null) {
      stream = _asBroadcastAnswersStream(provided).map((answers) {
        final filtered = answers
            .where((answer) => !answer.isDeleted)
            .where(_matchesActiveAnswerRole)
            .toList();
        return sortLessonQuestionAnswers(filtered, _myAnswersSort);
      });
    } else if (Firebase.apps.isEmpty) {
      stream = Stream.value(const []);
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        stream = Stream.value(const []);
      } else {
        final ownAnswersStream = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestionAnswers')
            .where('courseId', isEqualTo: _courseId)
            .where('lessonNumber', isEqualTo: widget.lessonNumber)
            .snapshots(includeMetadataChanges: true)
            .map((snapshot) {
              return snapshot.docs
                  .map(LessonQuestionAnswer.fromFirestore)
                  .where((answer) => !answer.isDeleted)
                  .toList();
            });
        final ownMirroredAnswersStream = FirebaseFirestore.instance
            .collection('publicLessonQuestionAnswers')
            .where('courseId', isEqualTo: _courseId)
            .where('lessonNumber', isEqualTo: widget.lessonNumber)
            .where('authorId', isEqualTo: user.uid)
            .where('isDeleted', isEqualTo: false)
            .snapshots(includeMetadataChanges: true)
            .map((snapshot) {
              return snapshot.docs
                  .map(LessonQuestionAnswer.fromFirestore)
                  .where((answer) => !answer.isDeleted)
                  .toList();
            });
        stream = Stream.multi((controller) {
          var latestOwnAnswers = const <LessonQuestionAnswer>[];
          var latestMirroredAnswers = const <LessonQuestionAnswer>[];
          void emitMergedAnswers() {
            final mergedById = <String, LessonQuestionAnswer>{};
            for (final answer in latestOwnAnswers) {
              final answerId = (answer.id ?? '').trim();
              if (answerId.isNotEmpty) {
                mergedById[answerId] = answer;
              }
            }
            for (final answer in latestMirroredAnswers) {
              final answerId = (answer.id ?? '').trim();
              if (answerId.isNotEmpty) {
                mergedById[answerId] = answer;
              }
            }
            final filtered = mergedById.values
                .where(_matchesActiveAnswerRole)
                .toList();
            controller.add(sortLessonQuestionAnswers(filtered, _myAnswersSort));
          }

          final ownSubscription = ownAnswersStream.listen((answers) {
            latestOwnAnswers = answers;
            emitMergedAnswers();
          }, onError: controller.addError);
          final mirroredSubscription = ownMirroredAnswersStream.listen((
            answers,
          ) {
            latestMirroredAnswers = answers;
            emitMergedAnswers();
          }, onError: controller.addError);
          controller.onCancel = () async {
            await ownSubscription.cancel();
            await mirroredSubscription.cancel();
          };
        });
      }
    }
    final tracked = stream.map((answers) {
      _lastMyAnswers = answers;
      return answers;
    });
    final broadcast = tracked.asBroadcastStream();
    _cachedMyAnswersStream = broadcast;
    _cachedMyAnswersStreamKey = cacheKey;
    return broadcast;
  }

  Stream<Map<String, LessonQuestion>> _myAnswerQuestionsStream() {
    final cacheKey = Object.hash(
      widget.questionsStream,
      widget.publicQuestionsStream,
      _questionStreamScopeKey,
      'myAnswersQuestionMap',
    );
    if (_cachedMyAnswerQuestionsStream != null &&
        _cachedMyAnswerQuestionsStreamKey == cacheKey) {
      return _cachedMyAnswerQuestionsStream!;
    }

    final providedOwnQuestions = widget.questionsStream;
    final ownQuestionsStream = providedOwnQuestions != null
        ? _asBroadcastQuestionsStream(providedOwnQuestions, isPublic: false)
        : Firebase.apps.isEmpty
        ? Stream.value(const <LessonQuestion>[])
        : () {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              return Stream.value(const <LessonQuestion>[]);
            }
            return FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('lessonQuestions')
                .where('courseId', isEqualTo: _courseId)
                .where('lessonNumber', isEqualTo: widget.lessonNumber)
                .where('isDeleted', isEqualTo: false)
                .snapshots(includeMetadataChanges: true)
                .map(
                  (snapshot) =>
                      snapshot.docs.map(LessonQuestion.fromFirestore).toList(),
                );
          }();

    final providedPublicQuestions = widget.publicQuestionsStream;
    final publicQuestionsStream = providedPublicQuestions != null
        ? _asBroadcastQuestionsStream(providedPublicQuestions, isPublic: true)
        : Firebase.apps.isEmpty
        ? Stream.value(const <LessonQuestion>[])
        : FirebaseFirestore.instance
              .collection('publicLessonQuestions')
              .where('courseId', isEqualTo: _courseId)
              .where('lessonNumber', isEqualTo: widget.lessonNumber)
              .where('interactionSettingId', isEqualTo: _interactionSettingId)
              .where('isDeleted', isEqualTo: false)
              .snapshots(includeMetadataChanges: true)
              .map(
                (snapshot) =>
                    snapshot.docs.map(LessonQuestion.fromFirestore).toList(),
              );

    final stream = Stream<Map<String, LessonQuestion>>.multi((controller) {
      var latestOwnQuestions = const <LessonQuestion>[];
      var latestPublicQuestions = const <LessonQuestion>[];

      void emitQuestionMap() {
        final merged = <String, LessonQuestion>{};
        for (final question in latestOwnQuestions) {
          final questionId = (question.id ?? '').trim();
          if (questionId.isNotEmpty && !question.isDeleted) {
            merged[questionId] = question;
          }
        }
        for (final question in latestPublicQuestions) {
          final questionId = (question.id ?? '').trim();
          if (questionId.isNotEmpty && !question.isDeleted) {
            merged[questionId] = question;
          }
        }
        controller.add(merged);
      }

      final ownSubscription = ownQuestionsStream.listen((questions) {
        latestOwnQuestions = questions;
        emitQuestionMap();
      }, onError: controller.addError);
      final publicSubscription = publicQuestionsStream.listen((questions) {
        latestPublicQuestions = questions;
        emitQuestionMap();
      }, onError: controller.addError);
      controller.onCancel = () async {
        await ownSubscription.cancel();
        await publicSubscription.cancel();
      };
    });

    final tracked = stream.map<Map<String, LessonQuestion>>((questions) {
      _lastMyAnswerQuestions = questions;
      return questions;
    });
    final broadcast = tracked.asBroadcastStream();
    _cachedMyAnswerQuestionsStream = broadcast;
    _cachedMyAnswerQuestionsStreamKey = cacheKey;
    return broadcast;
  }

  Stream<LessonQuestionAnswer?> _myAnswerParentSnapshotStream({
    required String answerId,
    required String currentUserId,
  }) {
    if (Firebase.apps.isEmpty || answerId.isEmpty) {
      return Stream.value(null);
    }
    final firestore = FirebaseFirestore.instance;
    final privateStream = firestore
        .collection('users')
        .doc(currentUserId)
        .collection('lessonQuestionAnswers')
        .doc(answerId)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.exists
              ? LessonQuestionAnswer.fromFirestore(snapshot)
              : null,
        );
    final publicStream = firestore
        .collection('publicLessonQuestionAnswers')
        .doc(answerId)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.exists
              ? LessonQuestionAnswer.fromFirestore(snapshot)
              : null,
        );
    return Stream.multi((controller) {
      LessonQuestionAnswer? latestPrivate;
      LessonQuestionAnswer? latestPublic;
      void emitResolved() {
        final resolved = latestPublic ?? latestPrivate;
        if (resolved == null || resolved.isDeleted) {
          controller.add(null);
          return;
        }
        controller.add(resolved);
      }

      final privateSubscription = privateStream.listen((answer) {
        latestPrivate = answer;
        emitResolved();
      }, onError: controller.addError);
      final publicSubscription = publicStream.listen((answer) {
        latestPublic = answer;
        emitResolved();
      }, onError: controller.addError);
      controller.onCancel = () async {
        await privateSubscription.cancel();
        await publicSubscription.cancel();
      };
    });
  }

  Stream<Map<String, LessonQuestionAnswer>> _myAnswerParentAnswersStream() {
    final cacheKey = Object.hash(
      widget.answersStream,
      _questionStreamScopeKey,
      'myAnswerParentAnswers',
    );
    if (_cachedMyAnswerParentsStream != null &&
        _cachedMyAnswerParentsStreamKey == cacheKey) {
      return _cachedMyAnswerParentsStream!;
    }
    final provided = widget.answersStream;
    late final Stream<Map<String, LessonQuestionAnswer>> stream;
    if (provided != null) {
      stream = _asBroadcastAnswersStream(provided).map((answers) {
        final map = <String, LessonQuestionAnswer>{};
        for (final answer in answers) {
          final answerId = (answer.id ?? '').trim();
          if (answerId.isEmpty || answer.isDeleted) {
            continue;
          }
          map[answerId] = answer;
        }
        return map;
      });
    } else if (Firebase.apps.isEmpty) {
      stream = Stream.value(const <String, LessonQuestionAnswer>{});
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        stream = Stream.value(const <String, LessonQuestionAnswer>{});
      } else {
        stream = Stream.multi((controller) {
          final parentSubscriptions =
              <String, StreamSubscription<LessonQuestionAnswer?>>{};
          final parentAnswers = <String, LessonQuestionAnswer>{};

          void emitParentAnswers() {
            controller.add(
              Map<String, LessonQuestionAnswer>.from(parentAnswers),
            );
          }

          void syncParentIds(Set<String> parentIds) {
            final activeIds = parentSubscriptions.keys.toSet();
            for (final removedId in activeIds.difference(parentIds)) {
              final removedSubscription = parentSubscriptions.remove(removedId);
              if (removedSubscription != null) {
                unawaited(removedSubscription.cancel());
              }
              parentAnswers.remove(removedId);
            }
            for (final addedId in parentIds.difference(activeIds)) {
              parentSubscriptions[addedId] =
                  _myAnswerParentSnapshotStream(
                    answerId: addedId,
                    currentUserId: user.uid,
                  ).listen((resolvedParent) {
                    if (resolvedParent == null) {
                      parentAnswers.remove(addedId);
                    } else {
                      parentAnswers[addedId] = resolvedParent;
                    }
                    emitParentAnswers();
                  }, onError: controller.addError);
            }
            emitParentAnswers();
          }

          final answersSubscription = _myAnswersStream().listen((answers) {
            final parentIds = <String>{};
            for (final answer in answers) {
              if (answer.parentCommentType != 'answer') {
                continue;
              }
              final parentId = (answer.parentCommentId ?? '').trim();
              if (parentId.isNotEmpty) {
                parentIds.add(parentId);
              }
            }
            syncParentIds(parentIds);
          }, onError: controller.addError);

          controller.onCancel = () async {
            await answersSubscription.cancel();
            for (final subscription in parentSubscriptions.values) {
              await subscription.cancel();
            }
          };
        });
      }
    }
    final tracked = stream.map((answersById) {
      _lastMyAnswerParentAnswers = answersById;
      return answersById;
    });
    final broadcast = tracked.asBroadcastStream();
    _cachedMyAnswerParentsStream = broadcast;
    _cachedMyAnswerParentsStreamKey = cacheKey;
    return broadcast;
  }

  String get _interactionSettingId =>
      _lessonInteractionService.settingDocumentId(
        courseId: _courseId,
        lessonNumber: widget.lessonNumber,
      );

  Stream<List<LessonQuestion>> _publicQuestionsStream() {
    final cacheKey = Object.hash(
      widget.publicQuestionsStream,
      _questionStreamScopeKey,
      _publicQuestionsSort,
    );
    if (_cachedPublicQuestionsStream != null &&
        _cachedPublicQuestionsStreamKey == cacheKey) {
      return _cachedPublicQuestionsStream!;
    }
    final provided = widget.publicQuestionsStream;
    late final Stream<List<LessonQuestion>> stream;
    if (provided != null) {
      stream = _asBroadcastQuestionsStream(provided, isPublic: true).map((
        questions,
      ) {
        final filtered = widget.isTeacherPreview
            ? questions.where((question) => !question.isDeleted).toList()
            : questions
                  .where((question) => question.isPubliclyVisible)
                  .toList();
        final sorted = sortLessonQuestions(filtered, _publicQuestionsSort);
        _lastPublicQuestions = sorted;
        return sorted;
      });
    } else if (Firebase.apps.isEmpty) {
      stream = Stream.value(const []);
    } else {
      stream = FirebaseFirestore.instance
          .collection('publicLessonQuestions')
          .where('courseId', isEqualTo: _courseId)
          .where('lessonNumber', isEqualTo: widget.lessonNumber)
          .where('interactionSettingId', isEqualTo: _interactionSettingId)
          .where('studentVisibility', isEqualTo: lessonQuestionVisibilityPublic)
          .where('moderationStatus', isEqualTo: lessonNoteModerationVisible)
          .where('isDeleted', isEqualTo: false)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            if (snapshot.metadata.isFromCache) {
              return _lastPublicQuestions;
            }
            final questions = sortLessonQuestions(
              snapshot.docs
                  .map(LessonQuestion.fromFirestore)
                  .where((question) => question.isPubliclyVisible)
                  .toList(),
              _publicQuestionsSort,
            );
            _lastPublicQuestions = questions;
            return questions;
          });
    }
    final broadcast = stream.asBroadcastStream();
    _cachedPublicQuestionsStream = broadcast;
    _cachedPublicQuestionsStreamKey = cacheKey;
    return broadcast;
  }

  Stream<Set<String>> _teacherHiddenOwnQuestionIdsStream() {
    final cacheKey = Object.hash(
      widget.teacherHiddenOwnQuestionIdsStream,
      _questionStreamScopeKey,
    );
    if (_cachedTeacherHiddenOwnQuestionIdsStream != null &&
        _cachedTeacherHiddenOwnQuestionIdsStreamKey == cacheKey) {
      return _cachedTeacherHiddenOwnQuestionIdsStream!;
    }
    _lastTeacherHiddenOwnQuestionIds = const <String>{};
    final provided = widget.teacherHiddenOwnQuestionIdsStream;
    late final Stream<Set<String>> stream;
    if (provided != null) {
      stream = provided;
    } else if (Firebase.apps.isEmpty) {
      stream = Stream.value(const <String>{});
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        stream = Stream.value(const <String>{});
      } else {
        stream = FirebaseFirestore.instance
            .collection('publicLessonQuestions')
            .where('courseId', isEqualTo: _courseId)
            .where('lessonNumber', isEqualTo: widget.lessonNumber)
            .where('interactionSettingId', isEqualTo: _interactionSettingId)
            .where('authorId', isEqualTo: user.uid)
            .where(
              'moderationStatus',
              isEqualTo: lessonNoteModerationHiddenByTeacher,
            )
            .where('isDeleted', isEqualTo: false)
            .snapshots(includeMetadataChanges: true)
            .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
      }
    }
    final tracked = stream.map((ids) {
      _lastTeacherHiddenOwnQuestionIds = Set<String>.from(ids);
      return _lastTeacherHiddenOwnQuestionIds;
    });
    final broadcast = tracked.asBroadcastStream();
    _cachedTeacherHiddenOwnQuestionIdsStream = broadcast;
    _cachedTeacherHiddenOwnQuestionIdsStreamKey = cacheKey;
    return broadcast;
  }

  Stream<List<LessonQuestion>> _teacherPreviewPublicQuestionsStream() {
    final cacheKey = Object.hash(
      _questionStreamScopeKey,
      _publicQuestionsSort,
      'teacherPreview',
    );
    if (_cachedTeacherPreviewPublicQuestionsStream != null &&
        _cachedTeacherPreviewPublicQuestionsStreamKey == cacheKey) {
      return _cachedTeacherPreviewPublicQuestionsStream!;
    }
    late final Stream<List<LessonQuestion>> stream;
    if (Firebase.apps.isEmpty) {
      stream = Stream.value(const []);
    } else {
      stream = FirebaseFirestore.instance
          .collection('publicLessonQuestions')
          .where('courseId', isEqualTo: _courseId)
          .where('lessonNumber', isEqualTo: widget.lessonNumber)
          .where('interactionSettingId', isEqualTo: _interactionSettingId)
          .where('isDeleted', isEqualTo: false)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            if (snapshot.metadata.isFromCache) {
              return _lastTeacherPreviewPublicQuestions;
            }
            final questions = sortLessonQuestions(
              snapshot.docs.map(LessonQuestion.fromFirestore).toList(),
              _publicQuestionsSort,
            );
            _lastTeacherPreviewPublicQuestions = questions;
            return questions;
          });
    }
    final broadcast = stream.asBroadcastStream();
    _cachedTeacherPreviewPublicQuestionsStream = broadcast;
    _cachedTeacherPreviewPublicQuestionsStreamKey = cacheKey;
    return broadcast;
  }

  Stream<bool> _questionPublicPlatformEnabledStream() {
    final cacheKey = '$_courseId:${widget.lessonNumber}';
    if (_cachedQuestionPublicPlatformEnabledStream != null &&
        _cachedQuestionPublicPlatformEnabledStreamKey == cacheKey) {
      return _cachedQuestionPublicPlatformEnabledStream!;
    }
    final stream = _lessonInteractionService.publicFeatureEnabledStream(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonQuestionsPublicEnabledField,
    );
    final broadcast = stream.asBroadcastStream();
    _cachedQuestionPublicPlatformEnabledStream = broadcast;
    _cachedQuestionPublicPlatformEnabledStreamKey = cacheKey;
    return broadcast;
  }

  Stream<List<LessonNote>> _quotableNotesStream() {
    final provided = widget.quotableNotesStream;
    final canAccessTeacherOnlyPublicNotes =
        _canAccessTeacherOnlyQuotablePublicNotes;
    if (provided != null) {
      return provided.map(
        (notes) => sortLessonNotesByUpdatedAt(
          _quotableCandidateNotes(
            notes,
            currentUserId: _currentUserId,
            canAccessTeacherOnlyPublicNotes: canAccessTeacherOnlyPublicNotes,
          ),
        ),
      );
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const []);
    }
    var publicNotesQuery = FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .where('interactionSettingId', isEqualTo: _interactionSettingId)
        .where('moderationStatus', isEqualTo: lessonNoteModerationVisible)
        .where('isDeleted', isEqualTo: false)
        .where('allowsQuestionCitation', isEqualTo: true);
    if (!canAccessTeacherOnlyPublicNotes) {
      publicNotesQuery = publicNotesQuery.where(
        'studentVisibility',
        isEqualTo: lessonNoteVisibilityPublic,
      );
    }
    final publicNotesStream = publicNotesQuery
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final notes = snapshot.docs.map(LessonNote.fromFirestore).toList();
          if (snapshot.metadata.isFromCache) {
            if (_lastQuotablePublicNotes.isEmpty) {
              _lastQuotablePublicNotes = notes;
              return notes;
            }
            return _lastQuotablePublicNotes;
          }
          _lastQuotablePublicNotes = notes;
          return notes;
        });
    final ownNotesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .where('isDeleted', isEqualTo: false)
        .where('allowsQuestionCitation', isEqualTo: true)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final notes = snapshot.docs.map(LessonNote.fromFirestore).toList();
          if (snapshot.metadata.isFromCache) {
            if (_lastQuotableOwnNotes.isEmpty) {
              _lastQuotableOwnNotes = notes;
              return notes;
            }
            return _lastQuotableOwnNotes;
          }
          _lastQuotableOwnNotes = notes;
          return notes;
        });
    // Developer memo:
    // Older memo records can keep the same course/lesson text but have
    // different ID fields depending on the route they were created from.
    // This fallback stream keeps quote candidates stable by title scope,
    // while final posting validation still enforces strict safety checks.
    final ownLegacyNotesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonNotes')
        .where('courseTitle', isEqualTo: widget.course.title)
        .where('lessonTitle', isEqualTo: widget.lesson.title)
        .where('isDeleted', isEqualTo: false)
        .where('allowsQuestionCitation', isEqualTo: true)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final notes = snapshot.docs.map(LessonNote.fromFirestore).toList();
          if (snapshot.metadata.isFromCache) {
            if (_lastQuotableOwnLegacyNotes.isEmpty) {
              _lastQuotableOwnLegacyNotes = notes;
              return notes;
            }
            return _lastQuotableOwnLegacyNotes;
          }
          _lastQuotableOwnLegacyNotes = notes;
          return notes;
        });
    return Stream.multi((controller) {
      var latestPublicNotes = _lastQuotablePublicNotes;
      var latestOwnNotes = _lastQuotableOwnNotes;
      var latestOwnLegacyNotes = _lastQuotableOwnLegacyNotes;
      var hasPublicEmission = latestPublicNotes.isNotEmpty;
      var hasOwnEmission = latestOwnNotes.isNotEmpty;
      var hasOwnLegacyEmission = latestOwnLegacyNotes.isNotEmpty;
      void emit() {
        // Merge own-note streams by id so the dropdown does not fluctuate
        // when strict and legacy fallback queries return overlapping rows.
        final mergedOwnById = <String, LessonNote>{};
        for (final note in latestOwnNotes) {
          final noteId = (note.id ?? '').trim();
          if (noteId.isEmpty) {
            continue;
          }
          mergedOwnById[noteId] = note;
        }
        for (final note in latestOwnLegacyNotes) {
          final noteId = (note.id ?? '').trim();
          if (noteId.isEmpty) {
            continue;
          }
          mergedOwnById[noteId] = note;
        }
        controller.add(
          _mergeQuotableNotes(
            publicNotes: latestPublicNotes,
            ownNotes: mergedOwnById.values.toList(),
            currentUserId: user.uid,
            canAccessTeacherOnlyPublicNotes: canAccessTeacherOnlyPublicNotes,
          ),
        );
      }

      if (hasPublicEmission || hasOwnEmission || hasOwnLegacyEmission) {
        emit();
      }

      final publicSubscription = publicNotesStream.listen((notes) {
        latestPublicNotes = notes;
        hasPublicEmission = true;
        emit();
      }, onError: controller.addError);
      final ownSubscription = ownNotesStream.listen((notes) {
        latestOwnNotes = notes;
        hasOwnEmission = true;
        emit();
      }, onError: controller.addError);
      final ownLegacySubscription = ownLegacyNotesStream.listen((notes) {
        latestOwnLegacyNotes = notes;
        hasOwnLegacyEmission = true;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await publicSubscription.cancel();
        await ownSubscription.cancel();
        await ownLegacySubscription.cancel();
      };
    });
  }

  Future<bool> _isQuestionPublicPlatformEnabled() async {
    return _lessonInteractionService.isPublicFeatureEnabled(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonQuestionsPublicEnabledField,
    );
  }

  Future<Map<String, dynamic>?> _publicQuestionMirrorData(
    String questionId,
  ) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('publicLessonQuestions')
          .doc(questionId)
          .get();
      return snapshot.data();
    } on FirebaseException {
      return null;
    }
  }

  Future<bool> _isWritableQuestionMirror(String questionId) async {
    final data = await _publicQuestionMirrorData(questionId);
    return data != null &&
        data['isDeleted'] != true &&
        data['moderationStatus'] == lessonNoteModerationVisible;
  }

  Future<void> _setPublicQuestionModeration(LessonQuestion question) async {
    await _lessonInteractionService.setPublicModeration(
      collectionPath: 'publicLessonQuestions',
      documentId: question.id,
      moderationStatus: question.isTeacherHidden
          ? lessonNoteModerationVisible
          : lessonNoteModerationHiddenByTeacher,
    );
  }

  Future<void> _setPublicAnswerModeration(LessonQuestionAnswer answer) async {
    await _lessonInteractionService.setPublicModeration(
      collectionPath: 'publicLessonQuestionAnswers',
      documentId: answer.id,
      moderationStatus:
          answer.moderationStatus == lessonNoteModerationHiddenByTeacher
          ? lessonNoteModerationVisible
          : lessonNoteModerationHiddenByTeacher,
    );
  }

  Future<CourseParticipantIdentity> _loadParticipantIdentity(
    String learnerId,
  ) async {
    final safeLearnerId = learnerId.trim();
    if (Firebase.apps.isEmpty || safeLearnerId.isEmpty) {
      return CourseParticipantIdentity(
        courseId: _courseId,
        userId: safeLearnerId,
        identityMode: courseIdentityModeProfile,
        aliasConfiguredAtEnrollment: false,
        aliasRetired: false,
      );
    }
    final doc = await FirebaseFirestore.instance
        .collection('courses')
        .doc(_courseId)
        .collection('participantIdentities')
        .doc(safeLearnerId)
        .get();
    if (doc.exists) {
      return CourseParticipantIdentity.fromFirestore(doc);
    }
    return CourseParticipantIdentity(
      courseId: _courseId,
      userId: safeLearnerId,
      identityMode: courseIdentityModeProfile,
      aliasConfiguredAtEnrollment: false,
      aliasRetired: false,
    );
  }

  Future<void> _openRestrictionDetailsForAuthor({
    required String authorId,
    required String authorRole,
    required int lessonNumber,
  }) async {
    if (!widget.isTeacherPreview || !_isCurrentUserTeacher) {
      return;
    }
    final safeAuthorId = authorId.trim();
    if (safeAuthorId.isEmpty) {
      _showMessage('受講者情報を特定できないため設定を開けません。');
      return;
    }
    if (safeAuthorId == widget.course.instructorId || authorRole == 'teacher') {
      _showMessage('先生投稿は受講者制限の対象外です。');
      return;
    }
    final identity = await _loadParticipantIdentity(safeAuthorId);
    final currentMode = await _lessonInteractionService.learnerRestrictionMode(
      courseId: _courseId,
      lessonNumber: lessonNumber,
      learnerId: identity.userId,
    );
    if (!mounted) {
      return;
    }
    await _openLearnerRestrictionDialog(
      lessonNumber: lessonNumber,
      identity: identity,
      currentMode: currentMode,
    );
  }

  Future<void> _openLearnerRestrictionDialog({
    required int lessonNumber,
    required CourseParticipantIdentity identity,
    required String currentMode,
  }) async {
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final currentlyBulkHidden = await _lessonInteractionService
        .hasBulkHiddenPublicPosts(
          courseId: _courseId,
          lessonNumber: lessonNumber,
          learnerId: identity.userId,
        );
    var selectedMode = _lessonInteractionService
        .normalizeLearnerRestrictionMode(currentMode);
    var bulkHide = currentlyBulkHidden;
    var bulkUnhide = false;
    var bulkUnhidePolicy =
        LessonInteractionService.bulkUnhideKeepIndividualHidden;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('非公開詳細設定'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('対象ユーザー: ${identity.userId}'),
                    const SizedBox(height: 8),
                    Text('レッスン$lessonNumber'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '制限モード',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: LessonInteractionService
                              .learnerRestrictionModeNone,
                          child: Text('制限なし'),
                        ),
                        DropdownMenuItem(
                          value: LessonInteractionService
                              .learnerRestrictionModeNoPublicReadOrPost,
                          child: Text('公開欄の閲覧と投稿を制限'),
                        ),
                        DropdownMenuItem(
                          value: LessonInteractionService
                              .learnerRestrictionModeNoPublicPost,
                          child: Text('公開欄への投稿のみ制限'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedMode = _lessonInteractionService
                              .normalizeLearnerRestrictionMode(value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: bulkHide,
                      title: const Text('既存公開投稿を一括で非公開にする'),
                      onChanged: (value) {
                        setDialogState(() {
                          bulkHide = value == true;
                          if (bulkHide) {
                            bulkUnhide = false;
                          }
                        });
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: bulkUnhide,
                      title: const Text('既存公開投稿を一括で公開に戻す'),
                      onChanged: (value) {
                        setDialogState(() {
                          bulkUnhide = value == true;
                          if (bulkUnhide) {
                            bulkHide = false;
                          }
                        });
                      },
                    ),
                    if (bulkUnhide) ...[
                      const SizedBox(height: 8),
                      const Text('一括公開の方針'),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: LessonInteractionService
                            .bulkUnhideKeepIndividualHidden,
                        groupValue: bulkUnhidePolicy,
                        title: const Text('A: 個別非公開は維持'),
                        onChanged: (value) {
                          setDialogState(() {
                            bulkUnhidePolicy =
                                value ??
                                LessonInteractionService
                                    .bulkUnhideKeepIndividualHidden;
                          });
                        },
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value:
                            LessonInteractionService.bulkUnhideForceAllVisible,
                        groupValue: bulkUnhidePolicy,
                        title: const Text('B: すべて公開に戻す'),
                        onChanged: (value) {
                          setDialogState(() {
                            bulkUnhidePolicy =
                                value ??
                                LessonInteractionService
                                    .bulkUnhideKeepIndividualHidden;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('保存する'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _lessonInteractionService.setLearnerRestrictionMode(
        courseId: _courseId,
        lessonNumber: lessonNumber,
        learnerId: identity.userId,
        restrictionMode: selectedMode,
        updatedByUserId: user.uid,
      );
      var affected = 0;
      if (bulkHide) {
        affected = await _lessonInteractionService
            .setBulkModerationForLearnerPublicPosts(
              courseId: _courseId,
              lessonNumber: lessonNumber,
              learnerId: identity.userId,
              hide: true,
            );
      } else if (bulkUnhide) {
        affected = await _lessonInteractionService
            .setBulkModerationForLearnerPublicPosts(
              courseId: _courseId,
              lessonNumber: lessonNumber,
              learnerId: identity.userId,
              hide: false,
              unhidePolicy: bulkUnhidePolicy,
            );
      }
      _showMessage(
        affected > 0 ? '設定を保存しました。公開状態更新: $affected件' : '設定を保存しました。',
      );
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? '設定の保存に失敗しました。');
    } catch (error) {
      _showMessage('設定の保存に失敗しました: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _message = message;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _postFailureMessage(
    FirebaseException error, {
    required String fallback,
  }) {
    if (error.code == 'permission-denied') {
      return '投稿できませんでした。引用メモの公開設定や公開範囲を確認して、もう一度お試しください。';
    }
    return error.message ?? fallback;
  }

  Future<bool> _saveQuestion(_LessonQuestionDraft draft) async {
    if (Firebase.apps.isEmpty) {
      _showMessage('質問保存にはログインとFirebase設定が必要です。');
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('質問保存にはログインが必要です。');
      return false;
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final questionRef = draft.questionId == null
          ? firestore
                .collection('users')
                .doc(user.uid)
                .collection('lessonQuestions')
                .doc()
          : firestore
                .collection('users')
                .doc(user.uid)
                .collection('lessonQuestions')
                .doc(draft.questionId);
      final questionId = questionRef.id;
      if (draft.questionId != null) {
        final now = FieldValue.serverTimestamp();
        final updateData = {'body': draft.body, 'updatedAt': now};
        final batch = firestore.batch()
          ..set(questionRef, updateData, SetOptions(merge: true));
        final publicRef = firestore
            .collection('publicLessonQuestions')
            .doc(questionId);
        final publicSnapshot = await publicRef.get();
        if (publicSnapshot.exists) {
          batch.set(publicRef, updateData, SetOptions(merge: true));
        }
        await batch.commit();
        if (mounted) {
          setState(() {
            _editingQuestion = null;
          });
        }
        _showMessage('質問本文を更新しました。');
        return true;
      }
      final platformEnabled = await _isQuestionPublicPlatformEnabled();
      final restrictionMode = await _currentLearnerRestrictionMode();
      final blocksPublicPost = _lessonInteractionService.blocksPublicPost(
        restrictionMode,
      );
      final requestedPublic =
          draft.target == LessonQuestionTarget.everyone ||
          draft.visibility == LessonQuestionVisibility.public;
      if (requestedPublic &&
          blocksPublicPost &&
          !widget.isTeacherPreview &&
          !_isCurrentUserTeacher) {
        _showMessage('先生により公開質問への投稿が制限されています。先生のみ公開で投稿してください。');
        return false;
      }
      final target = draft.target == LessonQuestionTarget.everyone
          ? lessonQuestionTargetEveryone
          : lessonQuestionTargetTeacher;
      final visibility = requestedPublic && platformEnabled
          ? lessonQuestionVisibilityPublic
          : lessonQuestionVisibilityTeacherOnly;
      final isQuotedNoteValid = await _validateQuotedNoteForQuestion(
        userId: user.uid,
        draft: draft,
        finalVisibility: visibility,
      );
      if (!isQuotedNoteValid) {
        return false;
      }
      final isTeacherQuestion =
          widget.isTeacherPreview || _isCurrentUserTeacher;
      final teacherDisplayName = isTeacherQuestion
          ? await _teacherCommentDisplayName(user)
          : null;
      final authorName = await _resolveCommentAuthorName(
        user,
        isTeacher: isTeacherQuestion,
        teacherDisplayName: teacherDisplayName,
      );
      final authorSnapshot = await _courseIdentityService.resolveAuthorSnapshot(
        courseId: _courseId,
        userId: user.uid,
        fallbackDisplayName: authorName,
        role: isTeacherQuestion
            ? publicUserProfileRoleTeacher
            : publicUserProfileRoleStudent,
      );
      final now = FieldValue.serverTimestamp();
      final data = {
        'userId': user.uid,
        'authorId': user.uid,
        'authorName': authorSnapshot.displayName,
        'authorDisplayName': isTeacherQuestion ? teacherDisplayName : null,
        'authorAvatarColorName': authorSnapshot.avatarColorName,
        'authorProfileVisible': authorSnapshot.profileVisible,
        'authorIdentityMode': authorSnapshot.identityMode,
        'authorRole': isTeacherQuestion ? 'teacher' : 'student',
        'courseId': _courseId,
        'courseTitle': widget.course.title,
        'lessonNumber': widget.lessonNumber,
        'lessonTitle': widget.lesson.title,
        'title': '',
        'body': draft.body,
        'visibility': visibility,
        'studentVisibility': visibility,
        'target': target,
        'attachmentTypes': draft.attachmentTypes,
        'quotedNoteId': draft.quotedNoteId,
        'quotedNoteTitle': draft.quotedNoteTitle,
        'quotedNoteBody': draft.quotedNoteBody,
        'status': lessonQuestionStatusOpen,
        'isDeleted': false,
        'moderationStatus': lessonNoteModerationVisible,
        'updatedAt': now,
        if (draft.questionId == null) ...{'answerCount': 0, 'createdAt': now},
      };
      final batch = firestore.batch()
        ..set(questionRef, data, SetOptions(merge: true));
      final publicRef = firestore
          .collection('publicLessonQuestions')
          .doc(questionId);
      final publicSnapshot = draft.questionId == null
          ? null
          : await publicRef.get();
      final publicData = publicSnapshot?.data();
      final publicModerationStatus =
          publicData?['moderationStatus'] as String? ??
          lessonNoteModerationVisible;
      batch.set(publicRef, {
        ...data,
        'questionId': questionId,
        'interactionSettingId': _interactionSettingId,
        'visibility': lessonQuestionVisibilityPublic,
        'studentVisibility': visibility,
        'moderationStatus': publicModerationStatus,
      }, SetOptions(merge: true));
      await batch.commit();
      if (mounted) {
        setState(() {
          _editingQuestion = null;
        });
      }
      _showMessage(
        visibility == lessonQuestionVisibilityPublic || platformEnabled
            ? '質問コメントを投稿しました。'
            : '先生により公開質問欄が非公開化されているため、先生にだけ公開で保存しました。',
      );
      return true;
    } on FirebaseException catch (error) {
      _showMessage(_postFailureMessage(error, fallback: '質問コメントの投稿に失敗しました。'));
      return false;
    } catch (error) {
      _showMessage('質問コメントの投稿に失敗しました: $error');
      return false;
    }
  }

  Future<void> _deleteQuestion(LessonQuestion question) async {
    if (Firebase.apps.isEmpty || question.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final publicRef = firestore
        .collection('publicLessonQuestions')
        .doc(question.id);
    final publicSnapshot = await publicRef.get();
    final now = FieldValue.serverTimestamp();
    final batch = firestore.batch()
      ..set(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestions')
            .doc(question.id),
        {'isDeleted': true, 'deletedAt': now, 'updatedAt': now},
        SetOptions(merge: true),
      );
    if (publicSnapshot.exists) {
      batch.set(publicRef, {
        'studentVisibility': lessonQuestionVisibilityTeacherOnly,
        'isDeleted': true,
        'deletedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Stream<List<LessonQuestionAnswer>> _answersStream(LessonQuestion question) {
    final provided = widget.answersStream;
    if (provided != null) {
      return _asBroadcastAnswersStream(provided);
    }
    if (Firebase.apps.isEmpty || question.id == null || question.isDeleted) {
      return Stream.value(const []);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const []);
    }
    if (question.isPublic) {
      Future<LessonQuestionAnswer?> resolveSupplementalAnswer({
        required String answerId,
        required bool requireCurrentUserAuthor,
        DocumentSnapshot<Map<String, dynamic>>? preferredPublicSnapshot,
      }) async {
        LessonQuestionAnswer? publicAnswer;
        try {
          final publicSnapshot =
              preferredPublicSnapshot ??
              await FirebaseFirestore.instance
                  .collection('publicLessonQuestionAnswers')
                  .doc(answerId)
                  .get();
          if (publicSnapshot.exists) {
            final answer = LessonQuestionAnswer.fromFirestore(publicSnapshot);
            if (!answer.isDeleted && answer.questionId == question.id) {
              publicAnswer = answer;
            }
          }
        } on FirebaseException {
          // Keep fallback checks below.
        }

        if (publicAnswer != null) {
          if (!requireCurrentUserAuthor || publicAnswer.authorId == user.uid) {
            return publicAnswer;
          }
        }
        if (!requireCurrentUserAuthor) {
          return null;
        }

        try {
          final privateSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lessonQuestionAnswers')
              .doc(answerId)
              .get();
          if (!privateSnapshot.exists) {
            return null;
          }
          final answer = LessonQuestionAnswer.fromFirestore(privateSnapshot);
          if (answer.isDeleted ||
              answer.questionId != question.id ||
              answer.authorId != user.uid) {
            return null;
          }
          return answer;
        } on FirebaseException {
          return null;
        }
      }

      final publicVisibleAnswersStream = FirebaseFirestore.instance
          .collection('publicLessonQuestionAnswers')
          .where('questionId', isEqualTo: question.id)
          .where('isDeleted', isEqualTo: false)
          .where('moderationStatus', isEqualTo: lessonNoteModerationVisible)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            final answers = snapshot.docs
                .map(LessonQuestionAnswer.fromFirestore)
                .where((answer) => !answer.isDeleted)
                .toList();
            answers.sort((a, b) {
              return timestampOrEpoch(
                a.createdAt,
              ).compareTo(timestampOrEpoch(b.createdAt));
            });
            _lastPublicAnswers = answers;
            return answers;
          });
      final ownHiddenAnswersStream = FirebaseFirestore.instance
          .collection('publicLessonQuestionAnswers')
          .where('questionId', isEqualTo: question.id)
          .where('authorId', isEqualTo: user.uid)
          .where('isDeleted', isEqualTo: false)
          .where(
            'moderationStatus',
            isEqualTo: lessonNoteModerationHiddenByTeacher,
          )
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => snapshot.docs
                .map(LessonQuestionAnswer.fromFirestore)
                .where((answer) => !answer.isDeleted)
                .toList(),
          );
      final highlightedAnswerId = (_currentHighlightedAnswerId ?? '').trim();
      final highlightedSupplementalStream = highlightedAnswerId.isEmpty
          ? Stream.value(const <LessonQuestionAnswer>[])
          : FirebaseFirestore.instance
                .collection('publicLessonQuestionAnswers')
                .doc(highlightedAnswerId)
                .snapshots(includeMetadataChanges: true)
                .asyncMap((snapshot) async {
                  final highlighted = await resolveSupplementalAnswer(
                    answerId: highlightedAnswerId,
                    requireCurrentUserAuthor: true,
                    preferredPublicSnapshot: snapshot,
                  );
                  if (highlighted == null) {
                    return const <LessonQuestionAnswer>[];
                  }
                  final supplemental = <LessonQuestionAnswer>[highlighted];
                  if (highlighted.parentCommentType == 'answer') {
                    final parentId = (highlighted.parentCommentId ?? '').trim();
                    if (parentId.isNotEmpty &&
                        parentId != highlightedAnswerId) {
                      final parent = await resolveSupplementalAnswer(
                        answerId: parentId,
                        requireCurrentUserAuthor: false,
                      );
                      if (parent != null) {
                        supplemental.add(parent);
                      }
                    }
                  }
                  return supplemental;
                });
      return Stream.multi((controller) {
        var latestPublicAnswers = const <LessonQuestionAnswer>[];
        var latestOwnHiddenAnswers = const <LessonQuestionAnswer>[];
        var latestSupplementalAnswers = const <LessonQuestionAnswer>[];
        void emitMergedAnswers() {
          final mergedById = <String, LessonQuestionAnswer>{};
          for (final answer in latestPublicAnswers) {
            final answerId = (answer.id ?? '').trim();
            if (answerId.isEmpty) {
              continue;
            }
            mergedById[answerId] = answer;
          }
          for (final answer in latestOwnHiddenAnswers) {
            final answerId = (answer.id ?? '').trim();
            if (answerId.isEmpty) {
              continue;
            }
            mergedById[answerId] = answer;
          }
          for (final supplemental in latestSupplementalAnswers) {
            final answerId = (supplemental.id ?? '').trim();
            if (answerId.isNotEmpty) {
              mergedById[answerId] = supplemental;
            }
          }
          final answers = mergedById.values.toList()
            ..sort(
              (a, b) => timestampOrEpoch(
                a.createdAt,
              ).compareTo(timestampOrEpoch(b.createdAt)),
            );
          controller.add(answers);
        }

        final publicSubscription = publicVisibleAnswersStream.listen((answers) {
          latestPublicAnswers = answers;
          emitMergedAnswers();
        }, onError: controller.addError);
        final ownHiddenSubscription = ownHiddenAnswersStream.listen((answers) {
          latestOwnHiddenAnswers = answers;
          emitMergedAnswers();
        }, onError: controller.addError);
        final supplementalSubscription = highlightedSupplementalStream.listen((
          answers,
        ) {
          latestSupplementalAnswers = answers;
          emitMergedAnswers();
        }, onError: controller.addError);
        controller.onCancel = () async {
          await publicSubscription.cancel();
          await ownHiddenSubscription.cancel();
          await supplementalSubscription.cancel();
        };
      });
    }
    final ownAnswersStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonQuestionAnswers')
        .where('questionId', isEqualTo: question.id)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map(LessonQuestionAnswer.fromFirestore)
              .where((answer) => !answer.isDeleted)
              .toList(),
        );
    final mirroredAnswersStream = FirebaseFirestore.instance
        .collection('publicLessonQuestionAnswers')
        .where('questionId', isEqualTo: question.id)
        .where('isDeleted', isEqualTo: false)
        .where('moderationStatus', isEqualTo: lessonNoteModerationVisible)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map(LessonQuestionAnswer.fromFirestore)
              .where((answer) => !answer.isDeleted)
              .toList(),
        );
    final ownHiddenMirroredAnswersStream = FirebaseFirestore.instance
        .collection('publicLessonQuestionAnswers')
        .where('questionId', isEqualTo: question.id)
        .where('authorId', isEqualTo: user.uid)
        .where('isDeleted', isEqualTo: false)
        .where(
          'moderationStatus',
          isEqualTo: lessonNoteModerationHiddenByTeacher,
        )
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map(LessonQuestionAnswer.fromFirestore)
              .where((answer) => !answer.isDeleted)
              .toList(),
        );
    return Stream.multi((controller) {
      var latestOwnAnswers = const <LessonQuestionAnswer>[];
      var latestMirroredAnswers = const <LessonQuestionAnswer>[];
      var latestOwnHiddenMirroredAnswers = const <LessonQuestionAnswer>[];
      void emitMergedAnswers() {
        final mergedById = <String, LessonQuestionAnswer>{};
        for (final answer in latestMirroredAnswers) {
          final answerId = (answer.id ?? '').trim();
          if (answerId.isEmpty) {
            continue;
          }
          mergedById[answerId] = answer;
        }
        for (final answer in latestOwnHiddenMirroredAnswers) {
          final answerId = (answer.id ?? '').trim();
          if (answerId.isEmpty) {
            continue;
          }
          mergedById[answerId] = answer;
        }
        for (final answer in latestOwnAnswers) {
          final answerId = (answer.id ?? '').trim();
          if (answerId.isEmpty) {
            continue;
          }
          mergedById.putIfAbsent(answerId, () => answer);
        }
        final answers = mergedById.values.toList()
          ..sort((a, b) {
            return timestampOrEpoch(
              a.createdAt,
            ).compareTo(timestampOrEpoch(b.createdAt));
          });
        controller.add(answers);
      }

      final ownSubscription = ownAnswersStream.listen((answers) {
        latestOwnAnswers = answers;
        emitMergedAnswers();
      }, onError: controller.addError);
      final mirroredSubscription = mirroredAnswersStream.listen((answers) {
        latestMirroredAnswers = answers;
        emitMergedAnswers();
      }, onError: controller.addError);
      final ownHiddenMirroredSubscription = ownHiddenMirroredAnswersStream
          .listen((answers) {
            latestOwnHiddenMirroredAnswers = answers;
            emitMergedAnswers();
          }, onError: controller.addError);
      controller.onCancel = () async {
        await ownSubscription.cancel();
        await mirroredSubscription.cancel();
        await ownHiddenMirroredSubscription.cancel();
      };
    });
  }

  Stream<List<LessonQuestionAnswer>> _teacherPreviewAnswersStream(
    LessonQuestion question,
  ) {
    final provided = widget.answersStream;
    if (provided != null) {
      return _asBroadcastAnswersStream(provided);
    }
    if (Firebase.apps.isEmpty || question.id == null || question.isDeleted) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('publicLessonQuestionAnswers')
        .where('questionId', isEqualTo: question.id)
        .where('isDeleted', isEqualTo: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final answers = snapshot.docs
              .map(LessonQuestionAnswer.fromFirestore)
              .where((answer) => !answer.isDeleted)
              .toList();
          answers.sort((a, b) {
            return timestampOrEpoch(
              a.createdAt,
            ).compareTo(timestampOrEpoch(b.createdAt));
          });
          _lastTeacherPreviewAnswers = answers;
          return answers;
        });
  }

  Future<LessonNote?> _resolveQuotedNoteForCurrentUser({
    required String userId,
    required String noteId,
  }) async {
    if (noteId.isEmpty || Firebase.apps.isEmpty) {
      return null;
    }
    final firestore = FirebaseFirestore.instance;
    try {
      final publicSnapshot = await firestore
          .collection('publicLessonNotes')
          .doc(noteId)
          .get();
      if (publicSnapshot.exists) {
        final publicNote = LessonNote.fromFirestore(publicSnapshot);
        if (!publicNote.isDeleted &&
            publicNote.allowsQuestionCitation &&
            publicNote.courseId == _courseId &&
            publicNote.lessonNumber == widget.lessonNumber) {
          return publicNote;
        }
      }
    } on FirebaseException {
      // Fall through to private lookup below.
    }
    try {
      final ownSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('lessonNotes')
          .doc(noteId)
          .get();
      if (ownSnapshot.exists) {
        final ownNote = LessonNote.fromFirestore(ownSnapshot);
        if (!ownNote.isDeleted &&
            ownNote.allowsQuestionCitation &&
            ownNote.courseId == _courseId &&
            ownNote.lessonNumber == widget.lessonNumber) {
          return ownNote;
        }
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  Future<LessonNote?> _loadQuotedNoteForMessage({
    required String userId,
    required String noteId,
  }) async {
    if (noteId.isEmpty || Firebase.apps.isEmpty) {
      return null;
    }
    final firestore = FirebaseFirestore.instance;
    try {
      final ownSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('lessonNotes')
          .doc(noteId)
          .get();
      if (ownSnapshot.exists) {
        return LessonNote.fromFirestore(ownSnapshot);
      }
    } on FirebaseException {
      // Keep fallback checks below.
    }
    try {
      final publicSnapshot = await firestore
          .collection('publicLessonNotes')
          .doc(noteId)
          .get();
      if (publicSnapshot.exists) {
        return LessonNote.fromFirestore(publicSnapshot);
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  bool _quotedNoteSnapshotMatches({
    required LessonNote note,
    required String? selectedTitle,
    required String? selectedBody,
  }) {
    final title = (selectedTitle ?? '').trim();
    final body = (selectedBody ?? '').trim();
    return title == note.title.trim() && body == note.body.trim();
  }

  String _quotedNotePublicAudienceMessage(LessonNote note) {
    if (note.isStudentTeacherOnly) {
      return '引用しようとしているメモは先生だけに公開されているため、公開コメントには使えません。';
    }
    return '引用しようとしているメモは公開コメントに使える条件を満たしていません。';
  }

  Future<String?> _quotedNoteValidationMessage({
    required String userId,
    required String quotedNoteId,
    required String? selectedTitle,
    required String? selectedBody,
    required bool requiresPublicAudience,
  }) async {
    final resolved = await _resolveQuotedNoteForCurrentUser(
      userId: userId,
      noteId: quotedNoteId,
    );
    if (resolved == null) {
      final note = await _loadQuotedNoteForMessage(
        userId: userId,
        noteId: quotedNoteId,
      );
      if (note == null) {
        return '引用メモを確認できないため、選び直してください。';
      }
      if (note.isDeleted) {
        return '引用しようとしているメモは削除されたため、使えません。';
      }
      if (!note.allowsQuestionCitation) {
        return '引用しようとしているメモは引用許可がオフになったため、使えません。';
      }
      if (note.courseId != _courseId ||
          note.lessonNumber != widget.lessonNumber) {
        return 'このレッスンのメモではないため、引用できません。';
      }
      return '引用メモを確認できないため、選び直してください。';
    }
    if (!_quotedNoteSnapshotMatches(
      note: resolved,
      selectedTitle: selectedTitle,
      selectedBody: selectedBody,
    )) {
      return '引用しようとしているメモの内容が更新されたため、もう一度選び直してください。';
    }
    if (requiresPublicAudience &&
        !canQuoteLessonNoteToPublicAudience(resolved)) {
      return _quotedNotePublicAudienceMessage(resolved);
    }
    return null;
  }

  Future<bool> _validateQuotedNoteForQuestion({
    required String userId,
    required _LessonQuestionDraft draft,
    required String finalVisibility,
  }) async {
    final quotedNoteId = (draft.quotedNoteId ?? '').trim();
    if (quotedNoteId.isEmpty) {
      return true;
    }
    final message = await _quotedNoteValidationMessage(
      userId: userId,
      quotedNoteId: quotedNoteId,
      selectedTitle: draft.quotedNoteTitle,
      selectedBody: draft.quotedNoteBody,
      requiresPublicAudience: finalVisibility == lessonQuestionVisibilityPublic,
    );
    if (message != null) {
      _showMessage(message);
      return false;
    }
    return true;
  }

  Future<bool> _validateQuotedNoteForAnswer({
    required String userId,
    required LessonQuestion question,
    required _LessonQuestionAnswerDraft draft,
  }) async {
    final quotedNoteId = (draft.quotedNoteId ?? '').trim();
    if (quotedNoteId.isEmpty) {
      return true;
    }
    final message = await _quotedNoteValidationMessage(
      userId: userId,
      quotedNoteId: quotedNoteId,
      selectedTitle: draft.quotedNoteTitle,
      selectedBody: draft.quotedNoteBody,
      requiresPublicAudience: question.isPubliclyVisible,
    );
    if (message != null) {
      _showMessage(message);
      return false;
    }
    return true;
  }

  Future<LessonQuestion?> _loadLatestReplyParentQuestion({
    required String questionId,
    required String currentUserId,
    required String expectedAuthorId,
  }) async {
    if (Firebase.apps.isEmpty || questionId.isEmpty) {
      return null;
    }
    final firestore = FirebaseFirestore.instance;
    try {
      final publicSnapshot = await firestore
          .collection('publicLessonQuestions')
          .doc(questionId)
          .get();
      if (publicSnapshot.exists) {
        return LessonQuestion.fromFirestore(publicSnapshot);
      }
    } on FirebaseException {
      // Fall back to private copy below.
    }
    if (expectedAuthorId != currentUserId) {
      return null;
    }
    try {
      final privateSnapshot = await firestore
          .collection('users')
          .doc(currentUserId)
          .collection('lessonQuestions')
          .doc(questionId)
          .get();
      if (privateSnapshot.exists) {
        return LessonQuestion.fromFirestore(privateSnapshot);
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  Future<LessonQuestionAnswer?> _loadLatestReplyParentAnswer({
    required String answerId,
    required String currentUserId,
    required String expectedAuthorId,
  }) async {
    if (Firebase.apps.isEmpty || answerId.isEmpty) {
      return null;
    }
    final firestore = FirebaseFirestore.instance;
    try {
      final publicSnapshot = await firestore
          .collection('publicLessonQuestionAnswers')
          .doc(answerId)
          .get();
      if (publicSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(publicSnapshot);
      }
    } on FirebaseException {
      // Fall back to private copy below.
    }
    if (expectedAuthorId != currentUserId) {
      return null;
    }
    try {
      final privateSnapshot = await firestore
          .collection('users')
          .doc(currentUserId)
          .collection('lessonQuestionAnswers')
          .doc(answerId)
          .get();
      if (privateSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(privateSnapshot);
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  Future<LessonQuestionAnswer?> _loadAnswerForThreadRoot({
    required String answerId,
    required String currentUserId,
  }) async {
    if (Firebase.apps.isEmpty || answerId.isEmpty) {
      return null;
    }
    final firestore = FirebaseFirestore.instance;
    try {
      final publicSnapshot = await firestore
          .collection('publicLessonQuestionAnswers')
          .doc(answerId)
          .get();
      if (publicSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(publicSnapshot);
      }
    } on FirebaseException {
      // Fall back to private copy below.
    }
    try {
      final privateSnapshot = await firestore
          .collection('users')
          .doc(currentUserId)
          .collection('lessonQuestionAnswers')
          .doc(answerId)
          .get();
      if (privateSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(privateSnapshot);
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  Future<String?> _resolveThreadRootAnswerIdForPersist({
    required LessonQuestion question,
    required _LessonQuestionAnswerDraft draft,
    required String currentUserId,
  }) async {
    if (draft.parentCommentType != 'answer') {
      return null;
    }
    final parentAnswerId = (draft.parentCommentId ?? '').trim();
    if (parentAnswerId.isEmpty) {
      return null;
    }

    final cachedAnswers = _fallbackAnswerMap();

    Future<LessonQuestionAnswer?> resolveAnswer(String answerId) async {
      final cached = cachedAnswers[answerId];
      if (cached != null) {
        return cached;
      }
      final loaded = await _loadAnswerForThreadRoot(
        answerId: answerId,
        currentUserId: currentUserId,
      );
      if (loaded != null) {
        final loadedId = (loaded.id ?? '').trim();
        if (loadedId.isNotEmpty) {
          cachedAnswers[loadedId] = loaded;
        }
      }
      return loaded;
    }

    var currentAnswerId = parentAnswerId;
    final visited = <String>{};
    for (var depth = 0; depth < 20; depth += 1) {
      if (!visited.add(currentAnswerId)) {
        return null;
      }
      final currentAnswer = await resolveAnswer(currentAnswerId);
      if (currentAnswer == null) {
        return null;
      }

      final explicitRootId = (currentAnswer.threadRootAnswerId ?? '').trim();
      if (explicitRootId.isNotEmpty) {
        final explicitRoot = await resolveAnswer(explicitRootId);
        if (explicitRoot == null ||
            !_isDirectAnswerToQuestion(explicitRoot, question)) {
          return null;
        }
        return explicitRootId;
      }

      if (_isDirectAnswerToQuestion(currentAnswer, question)) {
        final directId = (currentAnswer.id ?? '').trim();
        return directId.isEmpty ? null : directId;
      }
      if (currentAnswer.parentCommentType != 'answer') {
        return null;
      }
      final nextId = (currentAnswer.parentCommentId ?? '').trim();
      if (nextId.isEmpty) {
        return null;
      }
      currentAnswerId = nextId;
    }
    return null;
  }

  Future<String> _resolveReplyTargetDisplayNameForPersist({
    required LessonQuestion question,
    required _LessonQuestionAnswerDraft draft,
    required String currentUserId,
  }) async {
    // Keep the reply-time snapshot if we already resolved a usable name
    // before save. Parent authorName is only a last-resort fallback.
    final replyTimeResolved = _nonEmailDisplayName(draft.replyToDisplayName);
    if (replyTimeResolved != null) {
      return replyTimeResolved;
    }
    final fallback = _safeReplyTargetDisplayName(
      draft.replyToDisplayName,
      role: draft.replyToAuthorRole,
    );
    if (Firebase.apps.isEmpty) {
      return fallback;
    }
    final expectedAuthorId = (draft.replyToAuthorId ?? '').trim();
    if (draft.parentCommentType == 'answer') {
      final parentAnswerId = (draft.parentCommentId ?? '').trim();
      if (parentAnswerId.isEmpty) {
        return fallback;
      }
      final parentAnswer = await _loadLatestReplyParentAnswer(
        answerId: parentAnswerId,
        currentUserId: currentUserId,
        expectedAuthorId: expectedAuthorId,
      );
      if (parentAnswer == null) {
        return fallback;
      }
      return _safeReplyTargetDisplayName(
        parentAnswer.authorName,
        role: parentAnswer.authorRole,
      );
    }
    final parentQuestionId = (draft.parentCommentId ?? question.id ?? '')
        .trim();
    if (parentQuestionId.isEmpty) {
      return fallback;
    }
    final parentQuestion = await _loadLatestReplyParentQuestion(
      questionId: parentQuestionId,
      currentUserId: currentUserId,
      expectedAuthorId: expectedAuthorId,
    );
    if (parentQuestion == null) {
      return fallback;
    }
    return _safeReplyTargetDisplayName(
      parentQuestion.authorName,
      role: parentQuestion.authorRole,
    );
  }

  Future<bool> _saveAnswer(
    LessonQuestion question,
    _LessonQuestionAnswerDraft draft,
  ) async {
    if (!_canCurrentUserAnswerQuestion(question) ||
        Firebase.apps.isEmpty ||
        question.id == null ||
        draft.body.trim().isEmpty) {
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }
    try {
      final isTeacherAnswer = widget.isTeacherPreview || _isCurrentUserTeacher;
      final restrictionMode = await _currentLearnerRestrictionMode();
      final blocksPublicPost = _lessonInteractionService.blocksPublicPost(
        restrictionMode,
      );
      if (!isTeacherAnswer && blocksPublicPost && question.isPubliclyVisible) {
        _showMessage('先生により公開回答への投稿が制限されています。先生のみ公開の質問には回答できます。');
        return false;
      }
      final questionAuthorRestrictionMode =
          await _currentQuestionAuthorRestrictionMode(question);
      final blockedByQuestionAuthorRestriction =
          _isAnswerBlockedByQuestionAuthorRestriction(
            question: question,
            questionAuthorRestrictionMode: questionAuthorRestrictionMode,
            actingUserId: user.uid,
            isActingUserTeacher: isTeacherAnswer,
          );
      if (blockedByQuestionAuthorRestriction) {
        _showMessage('この公開質問は、質問投稿者が先生により公開欄への投稿を制限されているため、他の受講者は回答コメントできません。');
        return false;
      }
      final threadRootAnswerId = await _resolveThreadRootAnswerIdForPersist(
        question: question,
        draft: draft,
        currentUserId: user.uid,
      );
      final latestReplyTargetDisplayName =
          await _resolveReplyTargetDisplayNameForPersist(
            question: question,
            draft: draft,
            currentUserId: user.uid,
          );
      final isQuotedNoteValid = await _validateQuotedNoteForAnswer(
        userId: user.uid,
        question: question,
        draft: draft,
      );
      if (!isQuotedNoteValid) {
        return false;
      }
      final firestore = FirebaseFirestore.instance;
      final teacherDisplayName = isTeacherAnswer
          ? await _teacherCommentDisplayName(user)
          : null;
      final authorName = await _resolveCommentAuthorName(
        user,
        isTeacher: isTeacherAnswer,
        teacherDisplayName: teacherDisplayName,
      );
      final authorSnapshot = await _courseIdentityService.resolveAuthorSnapshot(
        courseId: _courseId,
        userId: user.uid,
        fallbackDisplayName: authorName,
        role: isTeacherAnswer
            ? publicUserProfileRoleTeacher
            : publicUserProfileRoleStudent,
      );
      final answerRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('lessonQuestionAnswers')
          .doc();
      final now = FieldValue.serverTimestamp();
      final data = {
        'questionId': question.id,
        'courseId': _courseId,
        'courseTitle': widget.course.title,
        'lessonNumber': widget.lessonNumber,
        'lessonTitle': widget.lesson.title,
        'authorId': user.uid,
        'authorName': authorSnapshot.displayName,
        'authorDisplayName': teacherDisplayName,
        'authorAvatarColorName': authorSnapshot.avatarColorName,
        'authorProfileVisible': authorSnapshot.profileVisible,
        'authorIdentityMode': authorSnapshot.identityMode,
        'authorRole': isTeacherAnswer ? 'teacher' : 'student',
        'body': draft.body.trim(),
        'attachmentTypes': <String>[],
        'parentCommentId': draft.parentCommentId,
        'parentCommentType': draft.parentCommentType,
        'replyToAuthorId': draft.replyToAuthorId,
        'replyToAuthorRole': draft.replyToAuthorRole,
        'replyToDisplayName': _safeReplyTargetDisplayName(
          latestReplyTargetDisplayName,
          role: draft.replyToAuthorRole,
        ),
        if ((draft.replyToBodyPreview ?? '').trim().isNotEmpty)
          'replyToBodyPreview': _previewText(draft.replyToBodyPreview!),
        if ((threadRootAnswerId ?? '').isNotEmpty)
          'threadRootAnswerId': threadRootAnswerId,
        'replyToCreatedAt': draft.replyToCreatedAt,
        'quotedNoteId': draft.quotedNoteId,
        'quotedNoteTitle': draft.quotedNoteTitle,
        'quotedNoteBody': draft.quotedNoteBody,
        'isDeleted': false,
        'moderationStatus': lessonNoteModerationVisible,
        'createdAt': now,
        'updatedAt': now,
      };
      final batch = firestore.batch()..set(answerRef, data);
      if (await _isWritableQuestionMirror(question.id!)) {
        batch.set(
          firestore.collection('publicLessonQuestionAnswers').doc(answerRef.id),
          {...data, 'answerId': answerRef.id},
        );
      }
      await batch.commit();
      return true;
    } on FirebaseException catch (error) {
      _showMessage(_postFailureMessage(error, fallback: '回答コメントの投稿に失敗しました。'));
      return false;
    } catch (error) {
      _showMessage('回答コメントの投稿に失敗しました: $error');
      return false;
    }
  }

  Future<String?> _teacherCommentDisplayName(User user) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('publicUserProfiles')
          .doc(
            publicUserProfileDocumentId(user.uid, publicUserProfileRoleTeacher),
          )
          .get();
      final profile = snapshot.exists
          ? PublicUserProfile.fromFirestore(snapshot)
          : fallbackPublicUserProfile(
              userId: user.uid,
              role: publicUserProfileRoleTeacher,
              displayName: _nonEmailDisplayName(user.displayName) ?? '先生',
            );
      final displayName = profile.displayName.trim();
      if (displayName.isEmpty ||
          displayName == '先生' ||
          _looksLikeEmail(displayName)) {
        return '先生';
      }
      if (displayName.endsWith('（先生）')) {
        return displayName;
      }
      return '$displayName（先生）';
    } on FirebaseException {
      final displayName = (user.displayName ?? '').trim();
      if (displayName.isEmpty || _looksLikeEmail(displayName)) {
        return '先生';
      }
      return displayName.endsWith('（先生）') ? displayName : '$displayName（先生）';
    }
  }

  Future<String> _resolveCommentAuthorName(
    User user, {
    required bool isTeacher,
    String? teacherDisplayName,
  }) async {
    if (isTeacher) {
      final safeTeacherName = _nonEmailDisplayName(teacherDisplayName);
      if (safeTeacherName != null) {
        return safeTeacherName;
      }
      return '先生';
    }

    final authName = _nonEmailDisplayName(user.displayName);
    if (authName != null) {
      return authName;
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = userDoc.data() ?? const <String, dynamic>{};
        final profileName = _nonEmailDisplayName(
          data['displayName']?.toString(),
        );
        if (profileName != null) {
          return profileName;
        }
        final nameField = _nonEmailDisplayName(data['name']?.toString());
        if (nameField != null) {
          return nameField;
        }
      } on FirebaseException {
        // Keep fallback below.
      }
    }

    final studentProfileName = await _resolvePublicProfileDisplayName(
      userId: user.uid,
      role: publicUserProfileRoleStudent,
    );
    if (studentProfileName != null) {
      return studentProfileName;
    }

    return '学習者';
  }

  Future<String?> _resolvePublicProfileDisplayName({
    required String userId,
    required String role,
  }) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('publicUserProfiles')
          .doc(publicUserProfileDocumentId(userId, role))
          .get();
      if (!snapshot.exists) {
        return null;
      }
      final profile = PublicUserProfile.fromFirestore(snapshot);
      return _nonEmailDisplayName(profile.displayName);
    } on FirebaseException {
      return null;
    }
  }

  String? _nonEmailDisplayName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || _looksLikeEmail(text)) {
      return null;
    }
    return text;
  }

  bool _looksLikeEmail(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return false;
    }
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
  }

  String _safeReplyTargetDisplayName(String? displayName, {String? role}) {
    final safeName = _nonEmailDisplayName(displayName);
    if (safeName != null) {
      return safeName;
    }
    if (role == 'teacher') {
      return '先生';
    }
    if (role == 'student') {
      return '学習者';
    }
    return '学習者';
  }

  bool _canCurrentUserAnswerQuestion(LessonQuestion question) {
    return canAnswerLessonQuestion(
      question: question,
      currentUserId: _currentUserId,
      isCurrentUserTeacher: _isCurrentUserTeacher,
      isTeacherPreview: widget.isTeacherPreview,
    );
  }

  Stream<LessonQuestion> _selectedQuestionStream(LessonQuestion question) {
    if (Firebase.apps.isEmpty || question.id == null) {
      return Stream.value(question);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (question.isPublic) {
      return FirebaseFirestore.instance
          .collection('publicLessonQuestions')
          .doc(question.id)
          .snapshots()
          .map((snapshot) {
            if (!snapshot.exists) {
              return question;
            }
            return LessonQuestion.fromFirestore(snapshot);
          });
    }
    if (user == null || user.uid != question.authorId) {
      return Stream.value(question);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonQuestions')
        .doc(question.id)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) {
            return question;
          }
          return LessonQuestion.fromFirestore(snapshot);
        });
  }

  Future<void> _deleteAnswer(LessonQuestionAnswer answer) async {
    if (Firebase.apps.isEmpty || answer.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != answer.authorId) {
      return;
    }
    await _markAnswerDeletedForOwner(
      answerId: answer.id!,
      ownerUserId: user.uid,
    );
  }

  Future<void> _markAnswerDeletedForOwner({
    required String answerId,
    required String ownerUserId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final deletedData = {
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final privateRef = firestore
        .collection('users')
        .doc(ownerUserId)
        .collection('lessonQuestionAnswers')
        .doc(answerId);
    final publicRef = firestore
        .collection('publicLessonQuestionAnswers')
        .doc(answerId);
    final publicSnapshot = await publicRef.get();
    final batch = firestore.batch()
      ..set(privateRef, deletedData, SetOptions(merge: true));
    if (publicSnapshot.exists) {
      batch.set(publicRef, deletedData, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _deleteAnswerFromMyList(LessonQuestionAnswer answer) async {
    if (Firebase.apps.isEmpty || answer.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != answer.authorId) {
      return;
    }
    await _markAnswerDeletedForOwner(
      answerId: answer.id!,
      ownerUserId: user.uid,
    );
  }

  bool _canOpenQuestionFromAnswerList(
    LessonQuestion question, {
    Set<String> teacherHiddenQuestionIds = const <String>{},
  }) {
    if (question.isDeleted) {
      return false;
    }
    if (widget.isTeacherPreview) {
      return true;
    }
    return !isQuestionTeacherHiddenForViewer(
      question: question,
      teacherHiddenQuestionIds: teacherHiddenQuestionIds,
    );
  }

  bool _canOpenAnswerFromAnswerList(
    LessonQuestionAnswer answer, {
    bool allowTeacherHidden = false,
  }) {
    if (answer.isDeleted) {
      return false;
    }
    if (widget.isTeacherPreview) {
      return true;
    }
    if (answer.moderationStatus == lessonInteractionModerationHiddenByTeacher) {
      return allowTeacherHidden;
    }
    return true;
  }

  Future<LessonQuestion?> _resolveQuestionForAnswer({
    required LessonQuestionAnswer answer,
    LessonQuestion? fallbackQuestion,
  }) async {
    if (fallbackQuestion != null && !fallbackQuestion.isDeleted) {
      return fallbackQuestion;
    }
    if (Firebase.apps.isEmpty || answer.questionId.isEmpty) {
      return fallbackQuestion;
    }
    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null) {
        final privateSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestions')
            .doc(answer.questionId)
            .get();
        if (privateSnapshot.exists) {
          final question = LessonQuestion.fromFirestore(privateSnapshot);
          if (!question.isDeleted) {
            return question;
          }
        }
      }
      final publicSnapshot = await FirebaseFirestore.instance
          .collection('publicLessonQuestions')
          .doc(answer.questionId)
          .get();
      if (!publicSnapshot.exists) {
        return null;
      }
      final question = LessonQuestion.fromFirestore(publicSnapshot);
      return question.isDeleted ? null : question;
    } on FirebaseException {
      return fallbackQuestion;
    }
  }

  Future<LessonQuestionAnswer?> _resolveParentAnswerForAnswer(
    LessonQuestionAnswer answer, {
    LessonQuestionAnswer? fallbackAnswer,
  }) async {
    if (answer.parentCommentType != 'answer') {
      return null;
    }
    final parentId = (answer.parentCommentId ?? '').trim();
    if (parentId.isEmpty) {
      return null;
    }
    if (fallbackAnswer != null &&
        (fallbackAnswer.id ?? '').trim() == parentId &&
        !fallbackAnswer.isDeleted) {
      return fallbackAnswer;
    }
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null) {
        final privateSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestionAnswers')
            .doc(parentId)
            .get();
        if (privateSnapshot.exists) {
          return LessonQuestionAnswer.fromFirestore(privateSnapshot);
        }
      }
      final publicSnapshot = await FirebaseFirestore.instance
          .collection('publicLessonQuestionAnswers')
          .doc(parentId)
          .get();
      if (publicSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(publicSnapshot);
      }
      return null;
    } on FirebaseException {
      return null;
    }
  }

  Future<LessonQuestionAnswer?> _resolveAnswerByIdForList(
    String answerId,
  ) async {
    final normalizedId = answerId.trim();
    if (normalizedId.isEmpty || Firebase.apps.isEmpty) {
      return null;
    }
    final cached = _fallbackAnswerMap()[normalizedId];
    if (cached != null) {
      return cached;
    }

    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null) {
        final privateSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestionAnswers')
            .doc(normalizedId)
            .get();
        if (privateSnapshot.exists) {
          return LessonQuestionAnswer.fromFirestore(privateSnapshot);
        }
      }
      final publicSnapshot = await FirebaseFirestore.instance
          .collection('publicLessonQuestionAnswers')
          .doc(normalizedId)
          .get();
      if (publicSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(publicSnapshot);
      }
      return null;
    } on FirebaseException {
      return null;
    }
  }

  Future<LessonQuestionAnswer?> _resolveThreadRootAnswerForList({
    required LessonQuestionAnswer answer,
    required LessonQuestion question,
    LessonQuestionAnswer? parentAnswer,
  }) async {
    if (answer.parentCommentType != 'answer') {
      return _isDirectAnswerToQuestion(answer, question) ? answer : null;
    }

    final explicitRootId = (answer.threadRootAnswerId ?? '').trim();
    if (explicitRootId.isNotEmpty) {
      final explicitRoot = await _resolveAnswerByIdForList(explicitRootId);
      if (explicitRoot == null ||
          !_isDirectAnswerToQuestion(explicitRoot, question)) {
        return null;
      }
      return explicitRoot;
    }

    var current = parentAnswer;
    final visitedIds = <String>{};
    for (var depth = 0; depth < 20; depth += 1) {
      if (current == null) {
        return null;
      }
      final currentId = (current.id ?? '').trim();
      if (currentId.isEmpty || !visitedIds.add(currentId)) {
        return null;
      }
      final currentExplicitRootId = (current.threadRootAnswerId ?? '').trim();
      if (currentExplicitRootId.isNotEmpty) {
        final currentExplicitRoot = await _resolveAnswerByIdForList(
          currentExplicitRootId,
        );
        if (currentExplicitRoot == null ||
            !_isDirectAnswerToQuestion(currentExplicitRoot, question)) {
          return null;
        }
        return currentExplicitRoot;
      }
      if (_isDirectAnswerToQuestion(current, question)) {
        return current;
      }
      if (current.parentCommentType != 'answer') {
        return null;
      }
      final nextId = (current.parentCommentId ?? '').trim();
      if (nextId.isEmpty) {
        return null;
      }
      current = await _resolveAnswerByIdForList(nextId);
    }
    return null;
  }

  Map<String, LessonQuestionAnswer> _fallbackAnswerMap() {
    final merged = <String, LessonQuestionAnswer>{};
    for (final answer in _lastMyAnswers) {
      final answerId = (answer.id ?? '').trim();
      if (answerId.isNotEmpty) {
        merged[answerId] = answer;
      }
    }
    for (final answer in _lastPublicAnswers) {
      final answerId = (answer.id ?? '').trim();
      if (answerId.isNotEmpty) {
        merged[answerId] = answer;
      }
    }
    for (final answer in _lastTeacherPreviewAnswers) {
      final answerId = (answer.id ?? '').trim();
      if (answerId.isNotEmpty) {
        merged[answerId] = answer;
      }
    }
    return merged;
  }

  String? _answerTapUnavailableMessage({
    required LessonQuestionAnswer answer,
    required LessonQuestion? question,
    required LessonQuestionAnswer? threadRootAnswer,
    Set<String> teacherHiddenQuestionIds = const <String>{},
  }) {
    if (!_canOpenAnswerFromAnswerList(answer, allowTeacherHidden: true)) {
      return 'この回答コメントは削除済み、または現在は表示できません。';
    }
    if (question == null ||
        !_canOpenQuestionFromAnswerList(
          question,
          teacherHiddenQuestionIds: teacherHiddenQuestionIds,
        )) {
      return '元の質問は削除済み、または現在は表示できません。';
    }
    if (answer.parentCommentType == 'answer' &&
        (threadRootAnswer == null ||
            !_canOpenAnswerFromAnswerList(threadRootAnswer))) {
      return '基準となる回答が削除済み、または現在は表示できません。';
    }
    return null;
  }

  Future<void> _openAnswerDetailFromList(
    LessonQuestionAnswer answer,
    ScrollController sourceController, {
    LessonQuestion? fallbackQuestion,
    Set<String> teacherHiddenQuestionIds = const <String>{},
  }) async {
    final answerId = (answer.id ?? '').trim();
    if (answerId.isEmpty || _openingAnswerDetailFromList) {
      return;
    }
    setState(() {
      _openingAnswerDetailFromList = true;
    });
    try {
      final cachedFallbackQuestion =
          fallbackQuestion ?? _fallbackMyAnswerQuestionMap()[answer.questionId];
      final question = await _resolveQuestionForAnswer(
        answer: answer,
        fallbackQuestion: cachedFallbackQuestion,
      );
      final parentAnswer = await _resolveParentAnswerForAnswer(
        answer,
        fallbackAnswer:
            _fallbackAnswerMap()[(answer.parentCommentId ?? '').trim()],
      );
      final threadRootAnswer = question == null
          ? null
          : await _resolveThreadRootAnswerForList(
              answer: answer,
              question: question,
              parentAnswer: parentAnswer,
            );
      final unavailableMessage = _answerTapUnavailableMessage(
        answer: answer,
        question: question,
        threadRootAnswer: threadRootAnswer,
        teacherHiddenQuestionIds: teacherHiddenQuestionIds,
      );
      if (unavailableMessage != null || question == null) {
        _showMessage(unavailableMessage ?? '元の質問を確認できませんでした。');
        return;
      }
      if (!mounted) {
        return;
      }
      _openQuestionDetail(
        question,
        sourceController,
        highlightedAnswerId: answerId,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingAnswerDetailFromList = false;
        });
      }
    }
  }

  Map<String, LessonQuestion> _fallbackMyAnswerQuestionMap() {
    final merged = <String, LessonQuestion>{};
    for (final question in _lastMyQuestions) {
      final questionId = (question.id ?? '').trim();
      if (questionId.isNotEmpty) {
        merged[questionId] = question;
      }
    }
    for (final question in _lastPublicQuestions) {
      final questionId = (question.id ?? '').trim();
      if (questionId.isNotEmpty) {
        merged[questionId] = question;
      }
    }
    for (final question in _lastTeacherPreviewPublicQuestions) {
      final questionId = (question.id ?? '').trim();
      if (questionId.isNotEmpty) {
        merged[questionId] = question;
      }
    }
    merged.addAll(_lastMyAnswerQuestions);
    return merged;
  }

  Map<String, LessonQuestionAnswer> _fallbackMyAnswerParentAnswerMap() {
    final merged = <String, LessonQuestionAnswer>{};
    merged.addAll(_fallbackAnswerMap());
    merged.addAll(_lastMyAnswerParentAnswers);
    return merged;
  }

  List<LessonNote> _latestQuotableNotesForInitialData() {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      return const <LessonNote>[];
    }
    final mergedOwnById = <String, LessonNote>{};
    for (final note in _lastQuotableOwnNotes) {
      final noteId = (note.id ?? '').trim();
      if (noteId.isEmpty) {
        continue;
      }
      mergedOwnById[noteId] = note;
    }
    for (final note in _lastQuotableOwnLegacyNotes) {
      final noteId = (note.id ?? '').trim();
      if (noteId.isEmpty) {
        continue;
      }
      mergedOwnById[noteId] = note;
    }
    return _mergeQuotableNotes(
      publicNotes: _lastQuotablePublicNotes,
      ownNotes: mergedOwnById.values.toList(),
      currentUserId: currentUserId,
      canAccessTeacherOnlyPublicNotes: _canAccessTeacherOnlyQuotablePublicNotes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.isTeacherPreview ? 420.0 : 560.0;
    final content = Card(
      margin: widget.isEmbedded ? EdgeInsets.zero : null,
      child: Padding(
        padding: widget.isEmbedded
            ? const EdgeInsets.only(top: 12)
            : EdgeInsets.zero,
        child: _buildContent(),
      ),
    );
    return widget.isEmbedded
        ? SizedBox(height: height, child: content)
        : content;
  }

  Widget _buildContent() {
    final selectedQuestion = _selectedQuestion;
    if (selectedQuestion != null) {
      return StreamBuilder<LessonQuestion>(
        stream: _selectedQuestionStream(selectedQuestion),
        builder: (context, snapshot) {
          final currentQuestion = snapshot.data ?? selectedQuestion;
          if (currentQuestion.isDeleted) {
            return _DeletedQuestionNotice(onBack: _backToQuestionList);
          }
          final isCurrentUserTeacher = widget.isTeacherPreview
              ? true
              : _isCurrentUserTeacher;
          return StreamBuilder<String>(
            stream: _questionAuthorRestrictionModeStream(currentQuestion),
            builder: (context, restrictionSnapshot) {
              final questionAuthorRestrictionMode =
                  restrictionSnapshot.data ??
                  LessonInteractionService.learnerRestrictionModeNone;
              final blockedByQuestionAuthorRestriction =
                  _isAnswerBlockedByQuestionAuthorRestriction(
                    question: currentQuestion,
                    questionAuthorRestrictionMode:
                        questionAuthorRestrictionMode,
                    actingUserId: _currentUserId,
                    isActingUserTeacher: isCurrentUserTeacher,
                  );
              return _LessonQuestionDetail(
                question: currentQuestion,
                answersStream: widget.isTeacherPreview
                    ? _teacherPreviewAnswersStream(currentQuestion)
                    : _answersStream(currentQuestion),
                quotableNotesStream: _sharedQuotableNotesStream,
                initialQuotableNotes: _latestQuotableNotesForInitialData(),
                currentUserId: _currentUserId,
                isCurrentUserTeacher: isCurrentUserTeacher,
                canAnswer:
                    _canCurrentUserAnswerQuestion(currentQuestion) &&
                    !blockedByQuestionAuthorRestriction,
                highlightedAnswerId: _currentHighlightedAnswerId,
                onBack: _backToQuestionList,
                onSaveAnswer: (draft) => _saveAnswer(currentQuestion, draft),
                onToggleQuestionModeration: widget.isTeacherPreview
                    ? () => _setPublicQuestionModeration(currentQuestion)
                    : null,
                onDeleteQuestion: () async {
                  await _deleteQuestion(currentQuestion);
                  if (mounted) {
                    _backToQuestionList();
                  }
                },
                onDeleteAnswer: _deleteAnswer,
                onToggleAnswerModeration: widget.isTeacherPreview
                    ? _setPublicAnswerModeration
                    : null,
              );
            },
          );
        },
      );
    }
    final editingQuestion = _editingQuestion;
    if (editingQuestion != null && !widget.isTeacherPreview) {
      return _LessonQuestionEditor(
        question: editingQuestion,
        course: widget.course,
        lesson: widget.lesson,
        lessonNumber: widget.lessonNumber,
        onCancel: () => setState(() => _editingQuestion = null),
        onSave: _saveQuestion,
        quotableNotesStream: _sharedQuotableNotesStream,
        initialQuotableNotes: _latestQuotableNotesForInitialData(),
        initialQuotedNote: widget.initialQuotedNote,
      );
    }
    return _buildQuestionList(isTeacherPreviewMode: widget.isTeacherPreview);
  }

  Widget _buildQuestionList({required bool isTeacherPreviewMode}) {
    final effectiveIsTeacher = isTeacherPreviewMode
        ? true
        : _isCurrentUserTeacher;
    return Column(
      children: [
        if (widget.isEmbedded) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.question_answer_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('質問コメント', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (isTeacherPreviewMode)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('先生プレビュー中は、質問コメントの確認と返信・管理ができます。'),
            ),
          ),
        TabBar(
          controller: _questionTabController,
          tabs: const [
            Tab(text: '自分の質問・回答'),
            Tab(text: '公開質問'),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '質問・回答を検索',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_message!),
                  ),
                ),
              if (_openingAnswerDetailFromList)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('回答詳細を開いています...'),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<Set<String>>(
                  stream: _teacherHiddenOwnQuestionIdsStream(),
                  builder: (context, hiddenSnapshot) {
                    final hiddenOwnQuestionIds =
                        hiddenSnapshot.data ?? _lastTeacherHiddenOwnQuestionIds;
                    return TabBarView(
                      controller: _questionTabController,
                      children: [
                        Builder(
                          builder: (context) {
                            if (_myCommentTab == _MyCommentTab.questions) {
                              return _QuestionList(
                                questionsStream: _questionsStream(),
                                fallbackQuestions: _lastMyQuestions,
                                questionFilter: _matchesActiveRole,
                                query: _query,
                                currentUserId: _currentUserId,
                                isCurrentUserTeacher: effectiveIsTeacher,
                                scrollController: _myQuestionsScrollController,
                                listStorageKey: isTeacherPreviewMode
                                    ? 'teacher-preview-my-questions'
                                    : 'my-questions',
                                teacherHiddenQuestionIds: hiddenOwnQuestionIds,
                                action: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildMyCommentTypeSelector(),
                                    const SizedBox(height: 8),
                                    _buildQuestionSortSelector(
                                      selectedSort: _myQuestionsSort,
                                      onSelected: (selection) {
                                        setState(() {
                                          _myQuestionsSort = selection;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    if (!isTeacherPreviewMode)
                                      FilledButton.icon(
                                        onPressed: () => setState(
                                          () => _editingQuestion =
                                              const LessonQuestion(
                                                authorId: '',
                                                authorName: '',
                                                courseId: '',
                                                courseTitle: '',
                                                lessonNumber: 1,
                                                lessonTitle: '',
                                                title: '',
                                                body: '',
                                                visibility:
                                                    LessonQuestionVisibility
                                                        .teacherOnly,
                                                target: LessonQuestionTarget
                                                    .teacher,
                                                attachmentTypes: [],
                                              ),
                                        ),
                                        icon: const Icon(Icons.add_comment),
                                        label: const Text('質問を作成'),
                                      )
                                    else
                                      const Text('先生として投稿した質問コメントを確認できます。'),
                                  ],
                                ),
                                emptyText: isTeacherPreviewMode
                                    ? '先生として投稿した質問コメントはまだありません。'
                                    : 'このレッスンの質問はまだありません。',
                                onTap: (question) => _openQuestionDetail(
                                  question,
                                  _myQuestionsScrollController,
                                ),
                                onDelete: _deleteQuestion,
                                onEdit: isTeacherPreviewMode
                                    ? null
                                    : (question) => setState(
                                        () => _editingQuestion = question,
                                      ),
                                onToggleModeration: isTeacherPreviewMode
                                    ? _setPublicQuestionModeration
                                    : null,
                                onOpenRestrictionSettings:
                                    isTeacherPreviewMode && effectiveIsTeacher
                                    ? (question) =>
                                          _openRestrictionDetailsForAuthor(
                                            authorId: question.authorId,
                                            authorRole: question.authorRole,
                                            lessonNumber: question.lessonNumber,
                                          )
                                    : null,
                              );
                            }
                            return _AnswerList(
                              answersStream: _myAnswersStream(),
                              fallbackAnswers: _lastMyAnswers,
                              questionMapStream: _myAnswerQuestionsStream(),
                              fallbackQuestionMap:
                                  _fallbackMyAnswerQuestionMap(),
                              parentAnswerMapStream:
                                  _myAnswerParentAnswersStream(),
                              fallbackParentAnswerMap:
                                  _fallbackMyAnswerParentAnswerMap(),
                              teacherHiddenQuestionIds: hiddenOwnQuestionIds,
                              answerFilter: _matchesActiveAnswerRole,
                              query: _query,
                              currentUserId: _currentUserId,
                              isCurrentUserTeacher: effectiveIsTeacher,
                              isTeacherPreview: isTeacherPreviewMode,
                              scrollController: _myAnswersScrollController,
                              listStorageKey: isTeacherPreviewMode
                                  ? 'teacher-preview-my-answers'
                                  : 'my-answers',
                              action: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildMyCommentTypeSelector(),
                                  const SizedBox(height: 8),
                                  _buildQuestionSortSelector(
                                    selectedSort: _myAnswersSort,
                                    onSelected: (selection) {
                                      setState(() {
                                        _myAnswersSort = selection;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              emptyText: isTeacherPreviewMode
                                  ? '先生として投稿した回答コメントはまだありません。'
                                  : 'このレッスンの回答コメントはまだありません。',
                              onTap: (answer, parentQuestion) =>
                                  _openAnswerDetailFromList(
                                    answer,
                                    _myAnswersScrollController,
                                    fallbackQuestion: parentQuestion,
                                    teacherHiddenQuestionIds:
                                        hiddenOwnQuestionIds,
                                  ),
                              onDelete: _deleteAnswerFromMyList,
                              onToggleModeration: isTeacherPreviewMode
                                  ? _setPublicAnswerModeration
                                  : null,
                              onOpenRestrictionSettings:
                                  isTeacherPreviewMode && effectiveIsTeacher
                                  ? (answer) =>
                                        _openRestrictionDetailsForAuthor(
                                          authorId: answer.authorId,
                                          authorRole: answer.authorRole,
                                          lessonNumber: answer.lessonNumber,
                                        )
                                  : null,
                              isOpeningAnswerDetail:
                                  _openingAnswerDetailFromList,
                            );
                          },
                        ),
                        StreamBuilder<bool>(
                          stream: _questionPublicPlatformEnabledStream(),
                          builder: (context, platformSnapshot) {
                            final enabled = platformSnapshot.data ?? true;
                            return StreamBuilder<String>(
                              stream: _learnerRestrictionModeStream(),
                              builder: (context, restrictionSnapshot) {
                                final restrictionMode =
                                    restrictionSnapshot.data ??
                                    LessonInteractionService
                                        .learnerRestrictionModeNone;
                                final blocksPublicRead =
                                    _lessonInteractionService.blocksPublicRead(
                                      restrictionMode,
                                    );
                                if (!enabled && !isTeacherPreviewMode) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      '先生により、このレッスンの公開質問欄は非公開化されています。',
                                    ),
                                  );
                                }
                                if (blocksPublicRead && !isTeacherPreviewMode) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      '先生により、このレッスンの公開質問の閲覧は制限されています。',
                                    ),
                                  );
                                }
                                return _QuestionList(
                                  questionsStream:
                                      isTeacherPreviewMode &&
                                          widget.publicQuestionsStream == null
                                      ? _teacherPreviewPublicQuestionsStream()
                                      : _publicQuestionsStream(),
                                  fallbackQuestions:
                                      isTeacherPreviewMode &&
                                          widget.publicQuestionsStream == null
                                      ? _lastTeacherPreviewPublicQuestions
                                      : _lastPublicQuestions,
                                  query: _query,
                                  currentUserId: _currentUserId,
                                  isCurrentUserTeacher: effectiveIsTeacher,
                                  scrollController: isTeacherPreviewMode
                                      ? _teacherPreviewPublicScrollController
                                      : _publicQuestionsScrollController,
                                  listStorageKey: isTeacherPreviewMode
                                      ? 'teacher-preview-public-questions'
                                      : 'public-questions',
                                  teacherHiddenQuestionIds:
                                      hiddenOwnQuestionIds,
                                  action: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildQuestionSortSelector(
                                        selectedSort: _publicQuestionsSort,
                                        onSelected: (selection) {
                                          setState(() {
                                            _publicQuestionsSort = selection;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      if (isTeacherPreviewMode)
                                        const Text(
                                          '質問コメントを確認し、返信や公開状態の管理ができます。',
                                        )
                                      else
                                        const Text('公開質問の一覧を確認できます。'),
                                    ],
                                  ),
                                  emptyText: '公開質問はまだありません。',
                                  onTap: (question) => _openQuestionDetail(
                                    question,
                                    isTeacherPreviewMode
                                        ? _teacherPreviewPublicScrollController
                                        : _publicQuestionsScrollController,
                                  ),
                                  onDelete: null,
                                  onEdit: null,
                                  onToggleModeration: isTeacherPreviewMode
                                      ? _setPublicQuestionModeration
                                      : null,
                                  onOpenRestrictionSettings:
                                      isTeacherPreviewMode && effectiveIsTeacher
                                      ? (question) =>
                                            _openRestrictionDetailsForAuthor(
                                              authorId: question.authorId,
                                              authorRole: question.authorRole,
                                              lessonNumber:
                                                  question.lessonNumber,
                                            )
                                      : null,
                                );
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMyCommentTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('質問'),
          selected: _myCommentTab == _MyCommentTab.questions,
          onSelected: (_) {
            setState(() {
              _myCommentTab = _MyCommentTab.questions;
            });
          },
        ),
        ChoiceChip(
          label: const Text('回答'),
          selected: _myCommentTab == _MyCommentTab.answers,
          onSelected: (_) {
            setState(() {
              _myCommentTab = _MyCommentTab.answers;
            });
          },
        ),
      ],
    );
  }

  Widget _buildQuestionSortSelector({
    required LessonQuestionSort selectedSort,
    required ValueChanged<LessonQuestionSort> onSelected,
  }) {
    return SegmentedButton<LessonQuestionSort>(
      segments: const [
        ButtonSegment(value: LessonQuestionSort.newest, label: Text('新しい順')),
        ButtonSegment(value: LessonQuestionSort.popular, label: Text('人気順')),
        ButtonSegment(
          value: LessonQuestionSort.editedNewest,
          label: Text('編集の新しい順'),
        ),
      ],
      selected: {selectedSort},
      onSelectionChanged: (selection) => onSelected(selection.first),
    );
  }
}

class _QuestionList extends StatelessWidget {
  const _QuestionList({
    required this.questionsStream,
    required this.query,
    required this.action,
    required this.emptyText,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.scrollController,
    required this.listStorageKey,
    this.fallbackQuestions = const <LessonQuestion>[],
    this.onToggleModeration,
    this.onOpenRestrictionSettings,
    this.teacherHiddenQuestionIds = const <String>{},
    this.questionFilter,
  });

  final Stream<List<LessonQuestion>> questionsStream;
  final String query;
  final Widget action;
  final String emptyText;
  final ValueChanged<LessonQuestion>? onTap;
  final ValueChanged<LessonQuestion>? onDelete;
  final ValueChanged<LessonQuestion>? onEdit;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final ScrollController scrollController;
  final String listStorageKey;
  final List<LessonQuestion> fallbackQuestions;
  final ValueChanged<LessonQuestion>? onToggleModeration;
  final ValueChanged<LessonQuestion>? onOpenRestrictionSettings;
  final Set<String> teacherHiddenQuestionIds;
  final bool Function(LessonQuestion question)? questionFilter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonQuestion>>(
      stream: questionsStream,
      builder: (context, snapshot) {
        final baseQuestions = snapshot.hasData
            ? (snapshot.data ?? const <LessonQuestion>[])
            : fallbackQuestions;
        final filter = questionFilter ?? ((_) => true);
        final questions = baseQuestions
            .where(filter)
            .where((question) => lessonQuestionMatchesQuery(question, query))
            .toList();
        return ListView(
          key: PageStorageKey<String>(listStorageKey),
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            action,
            const SizedBox(height: 16),
            if (questions.isEmpty)
              Text(emptyText)
            else
              for (final question in questions)
                Builder(
                  builder: (context) {
                    final isOwner = isCommentOwnerForActiveRole(
                      currentUserId: currentUserId,
                      isCurrentUserTeacher: isCurrentUserTeacher,
                      authorId: question.authorId,
                      authorRole: question.authorRole,
                    );
                    final questionId = (question.id ?? '').trim();
                    final isTeacherHidden = isQuestionTeacherHiddenForViewer(
                      question: question,
                      teacherHiddenQuestionIds: teacherHiddenQuestionIds,
                    );
                    final canOpenQuestion =
                        onTap != null &&
                        (isCurrentUserTeacher || !isTeacherHidden);
                    return _CommentBubble(
                      body: question.body,
                      authorId: question.authorId,
                      authorName: question.authorName,
                      authorDisplayName: question.authorDisplayName,
                      authorAvatarColorName: question.authorAvatarColorName,
                      authorProfileVisible: question.authorProfileVisible,
                      authorRole: question.authorRole,
                      postedAt: lessonQuestionPostedAt(question),
                      scopeLabel: _questionScopeLabel(
                        question,
                        forceTeacherHidden: isTeacherHidden,
                      ),
                      moderationNotice: isTeacherHidden ? '先生によって非公開中' : null,
                      attachmentTypes: question.attachmentTypes,
                      quotedNoteId: question.quotedNoteId,
                      quotedNoteTitle: question.quotedNoteTitle,
                      quotedNoteBody: question.quotedNoteBody,
                      isOwner: isOwner,
                      isTeacher: isCurrentUserTeacher,
                      onTap: canOpenQuestion ? () => onTap!(question) : null,
                      onReply: canOpenQuestion ? () => onTap!(question) : null,
                      onEdit: onEdit == null ? null : () => onEdit!(question),
                      onDelete: onDelete == null
                          ? null
                          : () => onDelete!(question),
                      onModerate: onToggleModeration == null
                          ? null
                          : () => onToggleModeration!(question),
                      onModerateDetails: onOpenRestrictionSettings == null
                          ? null
                          : () => onOpenRestrictionSettings!(question),
                      moderateLabel: question.isTeacherHidden
                          ? '公開に戻す'
                          : '非公開にする',
                    );
                  },
                ),
          ],
        );
      },
    );
  }
}

class _AnswerList extends StatelessWidget {
  const _AnswerList({
    required this.answersStream,
    required this.fallbackAnswers,
    required this.questionMapStream,
    required this.fallbackQuestionMap,
    required this.parentAnswerMapStream,
    required this.fallbackParentAnswerMap,
    required this.teacherHiddenQuestionIds,
    required this.query,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.isTeacherPreview,
    required this.scrollController,
    required this.listStorageKey,
    required this.action,
    required this.emptyText,
    required this.onTap,
    required this.onDelete,
    required this.onToggleModeration,
    required this.onOpenRestrictionSettings,
    this.isOpeningAnswerDetail = false,
    this.answerFilter,
  });

  final Stream<List<LessonQuestionAnswer>> answersStream;
  final List<LessonQuestionAnswer> fallbackAnswers;
  final Stream<Map<String, LessonQuestion>> questionMapStream;
  final Map<String, LessonQuestion> fallbackQuestionMap;
  final Stream<Map<String, LessonQuestionAnswer>> parentAnswerMapStream;
  final Map<String, LessonQuestionAnswer> fallbackParentAnswerMap;
  final Set<String> teacherHiddenQuestionIds;
  final String query;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final bool isTeacherPreview;
  final ScrollController scrollController;
  final String listStorageKey;
  final Widget action;
  final String emptyText;
  final Future<void> Function(
    LessonQuestionAnswer answer,
    LessonQuestion? question,
  )?
  onTap;
  final Future<void> Function(LessonQuestionAnswer answer)? onDelete;
  final ValueChanged<LessonQuestionAnswer>? onToggleModeration;
  final ValueChanged<LessonQuestionAnswer>? onOpenRestrictionSettings;
  final bool isOpeningAnswerDetail;
  final bool Function(LessonQuestionAnswer answer)? answerFilter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonQuestionAnswer>>(
      stream: answersStream,
      builder: (context, answerSnapshot) {
        final baseAnswers = answerSnapshot.hasData
            ? (answerSnapshot.data ?? const <LessonQuestionAnswer>[])
            : fallbackAnswers;
        final filter = answerFilter ?? ((_) => true);
        final answers = baseAnswers
            .where(filter)
            .where((answer) => lessonQuestionAnswerMatchesQuery(answer, query))
            .toList();
        return StreamBuilder<Map<String, LessonQuestion>>(
          stream: questionMapStream,
          builder: (context, questionSnapshot) {
            final questionMap = questionSnapshot.hasData
                ? (questionSnapshot.data ?? const <String, LessonQuestion>{})
                : fallbackQuestionMap;
            return StreamBuilder<Map<String, LessonQuestionAnswer>>(
              stream: parentAnswerMapStream,
              builder: (context, parentAnswerLookupSnapshot) {
                final parentAnswerLookup = parentAnswerLookupSnapshot.hasData
                    ? (parentAnswerLookupSnapshot.data ??
                          const <String, LessonQuestionAnswer>{})
                    : fallbackParentAnswerMap;
                final answerMap = <String, LessonQuestionAnswer>{
                  for (final answer in answers)
                    if ((answer.id ?? '').trim().isNotEmpty)
                      answer.id!.trim(): answer,
                };
                return ListView(
                  key: PageStorageKey<String>(listStorageKey),
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    action,
                    const SizedBox(height: 16),
                    if (answers.isEmpty)
                      Text(emptyText)
                    else
                      for (final answer in answers)
                        Builder(
                          builder: (context) {
                            final parentQuestion =
                                questionMap[answer.questionId];
                            final parentAnswerId =
                                (answer.parentCommentId ?? '').trim();
                            final parentAnswer =
                                answer.parentCommentType == 'answer'
                                ? answerMap[parentAnswerId] ??
                                      parentAnswerLookup[parentAnswerId]
                                : null;
                            final resolvedReplyTarget =
                                _resolvedReplyTargetDisplay(
                                  answer: answer,
                                  parentQuestion: parentQuestion,
                                  parentAnswer: parentAnswer,
                                );
                            final parentIsTeacherHidden =
                                parentQuestion != null &&
                                isQuestionTeacherHiddenForViewer(
                                  question: parentQuestion,
                                  teacherHiddenQuestionIds:
                                      teacherHiddenQuestionIds,
                                );
                            final questionScopeLabel = parentQuestion == null
                                ? '先生だけ表示'
                                : _questionScopeLabel(
                                    parentQuestion,
                                    forceTeacherHidden: parentIsTeacherHidden,
                                  );
                            final canOpenFromAnswerCard =
                                onTap != null &&
                                !isOpeningAnswerDetail &&
                                (isCurrentUserTeacher ||
                                    !parentIsTeacherHidden);
                            final isOwner = isCommentOwnerForActiveRole(
                              currentUserId: currentUserId,
                              isCurrentUserTeacher: isCurrentUserTeacher,
                              authorId: answer.authorId,
                              authorRole: answer.authorRole,
                            );
                            return _CommentBubble(
                              body: answer.body,
                              authorId: answer.authorId,
                              authorName: answer.authorName,
                              authorDisplayName: answer.authorDisplayName,
                              authorAvatarColorName:
                                  answer.authorAvatarColorName,
                              authorProfileVisible: answer.authorProfileVisible,
                              authorRole: answer.authorRole,
                              postedAt: lessonQuestionAnswerPostedAt(answer),
                              scopeLabel: answerScopeLabel(
                                answer,
                                questionScopeLabel,
                              ),
                              moderationNotice: answerModerationNotice(answer),
                              attachmentTypes: answer.attachmentTypes,
                              quotedNoteId: answer.quotedNoteId,
                              quotedNoteTitle: answer.quotedNoteTitle,
                              quotedNoteBody: answer.quotedNoteBody,
                              replyToAuthorId: answer.replyToAuthorId,
                              replyToDisplayName:
                                  resolvedReplyTarget.displayName,
                              replyToLinkCurrentProfile:
                                  resolvedReplyTarget.linkToCurrentProfile,
                              replyToAuthorRole: answer.replyToAuthorRole,
                              replyToBodyPreview: _replyBodyPreviewForDisplay(
                                answer: answer,
                                parentQuestion: parentQuestion,
                                parentAnswer: parentAnswer,
                              ),
                              isOwner: isOwner,
                              isTeacher: isCurrentUserTeacher,
                              onTap: canOpenFromAnswerCard
                                  ? () => onTap!(answer, parentQuestion)
                                  : null,
                              onReply: canOpenFromAnswerCard
                                  ? () => onTap!(answer, parentQuestion)
                                  : null,
                              onDelete: !isOwner || onDelete == null
                                  ? null
                                  : () => onDelete!(answer),
                              onModerate: onToggleModeration == null
                                  ? null
                                  : () => onToggleModeration!(answer),
                              onModerateDetails:
                                  onOpenRestrictionSettings == null
                                  ? null
                                  : () => onOpenRestrictionSettings!(answer),
                              moderateLabel:
                                  answer.moderationStatus ==
                                      lessonNoteModerationHiddenByTeacher
                                  ? '公開に戻す'
                                  : '非公開にする',
                            );
                          },
                        ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DeletedQuestionNotice extends StatelessWidget {
  const _DeletedQuestionNotice({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: '質問一覧に戻る',
              ),
              Text('質問詳細', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('この質問は削除済みのため、コメント欄では表示できません。'),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.postedAt,
    required this.scopeLabel,
    required this.attachmentTypes,
    required this.isOwner,
    required this.isTeacher,
    this.authorDisplayName,
    this.authorAvatarColorName,
    this.authorProfileVisible = true,
    this.quotedNoteId,
    this.quotedNoteTitle,
    this.quotedNoteBody,
    this.replyToAuthorId,
    this.replyToDisplayName,
    this.replyToLinkCurrentProfile = false,
    this.replyToAuthorRole,
    this.replyToBodyPreview,
    this.isHighlighted = false,
    this.isParentHighlighted = false,
    this.bubbleKey,
    this.onTap,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onModerate,
    this.onModerateDetails,
    this.moderateLabel,
    this.moderationNotice,
    this.bottomInlineAction,
  });

  final String body;
  final String authorId;
  final String authorName;
  final String? authorDisplayName;
  final String? authorAvatarColorName;
  final bool authorProfileVisible;
  final String authorRole;
  final Timestamp? postedAt;
  final String scopeLabel;
  final List<String> attachmentTypes;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
  final String? replyToAuthorId;
  final String? replyToDisplayName;
  final bool replyToLinkCurrentProfile;
  final String? replyToAuthorRole;
  final String? replyToBodyPreview;
  final bool isHighlighted;
  final bool isParentHighlighted;
  final Key? bubbleKey;
  final bool isOwner;
  final bool isTeacher;
  final VoidCallback? onTap;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onModerate;
  final VoidCallback? onModerateDetails;
  final String? moderateLabel;
  final String? moderationNotice;
  final Widget? bottomInlineAction;

  @override
  Widget build(BuildContext context) {
    final identityDisplayName = commentIdentityFor(
      authorId: authorId,
      authorName: authorName,
      authorDisplayName: authorDisplayName,
      authorRole: authorRole,
    ).displayName;
    final fallbackDisplayName =
        (!authorProfileVisible && authorRole != 'teacher')
        ? _sanitizeDisplayNameForUi(
            authorName,
            role: authorRole,
            fallback: '学習者',
          )
        : identityDisplayName;
    final profileRole = authorRole == publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    PublicUserProfile fallbackProfile() {
      final fallback = fallbackPublicUserProfile(
        userId: authorId,
        role: profileRole,
        displayName: fallbackDisplayName,
      );
      final avatarColorName = (authorAvatarColorName ?? '').trim();
      if (!profileAvatarColors.containsKey(avatarColorName)) {
        return fallback;
      }
      return PublicUserProfile(
        userId: fallback.userId,
        role: fallback.role,
        displayName: fallback.displayName,
        avatarColorName: avatarColorName,
        bio: fallback.bio,
        updatedAt: fallback.updatedAt,
      );
    }

    final staticProfile = fallbackProfile();
    final bubble = (!authorProfileVisible && authorRole != 'teacher')
        ? _buildBubble(
            context: context,
            profile: staticProfile,
            displayName: _commentDisplayName(
              profile: staticProfile,
              isOwner: isOwner,
              authorRole: authorRole,
            ),
          )
        : StreamBuilder<PublicUserProfile>(
            stream: publicUserProfileStream(
              userId: authorId,
              role: profileRole,
              fallbackDisplayName: fallbackDisplayName,
            ),
            builder: (context, snapshot) {
              final publicProfile = snapshot.data ?? staticProfile;
              return _buildBubble(
                context: context,
                profile: publicProfile,
                displayName: _commentDisplayName(
                  profile: publicProfile,
                  isOwner: isOwner,
                  authorRole: authorRole,
                ),
              );
            },
          );
    if (bubbleKey == null) {
      return bubble;
    }
    return KeyedSubtree(key: bubbleKey, child: bubble);
  }

  Widget _buildBubble({
    required BuildContext context,
    required PublicUserProfile profile,
    required String displayName,
  }) {
    final createdAtText = _formatCommentTimestamp(postedAt);
    final safeModerationNotice = (moderationNotice ?? '').trim();
    final canOperate =
        isOwner ||
        isTeacher ||
        onReply != null ||
        onModerate != null ||
        onModerateDetails != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: authorProfileVisible || authorRole == 'teacher'
                ? () {
                    showPublicUserProfilePreview(
                      context: context,
                      userId: authorId,
                      role: profile.role,
                      fallbackDisplayName: profile.displayName,
                      isOwner: isOwner,
                    );
                  }
                : null,
            child: PublicProfileAvatar(profile: profile),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 18, right: 32),
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Theme.of(context).colorScheme.primaryContainer
                                : isParentHighlighted
                                ? Colors.yellow.shade200
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            border: isHighlighted
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                : isParentHighlighted
                                ? Border.all(color: Colors.amber.shade700)
                                : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (replyToDisplayName != null) ...[
                                _ReplyLine(
                                  authorId: replyToAuthorId,
                                  displayName: replyToDisplayName!,
                                  linkToCurrentProfile:
                                      replyToLinkCurrentProfile,
                                  role: replyToAuthorRole,
                                  bodyPreview: replyToBodyPreview ?? '',
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(body.isEmpty ? '本文なし' : body),
                              if (attachmentTypes.isNotEmpty ||
                                  hasQuotedNoteAttachment(
                                    quotedNoteId: quotedNoteId,
                                    quotedNoteTitle: quotedNoteTitle,
                                    quotedNoteBody: quotedNoteBody,
                                  )) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final type in attachmentTypes)
                                      _AttachmentPreviewChip(
                                        label: type == lessonNoteAttachmentPdf
                                            ? 'PDF'
                                            : '画像',
                                        detail: 'アップロード機能追加後に表示します。',
                                      ),
                                    if (hasQuotedNoteAttachment(
                                      quotedNoteId: quotedNoteId,
                                      quotedNoteTitle: quotedNoteTitle,
                                      quotedNoteBody: quotedNoteBody,
                                    )) ...[
                                      _QuotedNotePreviewChip(
                                        quotedNoteId: quotedNoteId,
                                      ),
                                      PublicNoteEditStatusButton(
                                        noteId: quotedNoteId,
                                        fallbackTitle: quotedNoteDisplayTitle(
                                          quotedNoteId: quotedNoteId,
                                          quotedNoteTitle: quotedNoteTitle,
                                        ),
                                        fallbackBody: quotedNoteBody ?? '',
                                        icon: Icons.sticky_note_2_outlined,
                                        leadingLabel: 'メモ',
                                        compact: true,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                              if (bottomInlineAction != null) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: bottomInlineAction!,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 40,
                      top: 0,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            createdAtText,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (safeModerationNotice.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                safeModerationNotice,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canOperate)
                      Positioned(
                        right: 0,
                        top: 10,
                        child: PopupMenuButton<_CommentAction>(
                          tooltip: 'コメント操作',
                          onSelected: (action) {
                            switch (action) {
                              case _CommentAction.reply:
                                onReply?.call();
                              case _CommentAction.edit:
                                onEdit?.call();
                              case _CommentAction.delete:
                                onDelete?.call();
                              case _CommentAction.moderate:
                                onModerate?.call();
                              case _CommentAction.moderateDetails:
                                onModerateDetails?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            if (onReply != null)
                              const PopupMenuItem(
                                value: _CommentAction.reply,
                                child: Text('返信'),
                              ),
                            if (isOwner && onEdit != null)
                              const PopupMenuItem(
                                value: _CommentAction.edit,
                                child: Text('編集'),
                              ),
                            if ((isOwner || isTeacher) && onDelete != null)
                              const PopupMenuItem(
                                value: _CommentAction.delete,
                                child: Text('削除'),
                              ),
                            if (onModerate != null)
                              PopupMenuItem(
                                value: _CommentAction.moderate,
                                child: Text(moderateLabel ?? '公開状態を変更'),
                              ),
                            if (onModerateDetails != null)
                              const PopupMenuItem(
                                value: _CommentAction.moderateDetails,
                                child: Text('非公開詳細設定'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    scopeLabel,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CommentAction { reply, edit, delete, moderate, moderateDetails }

const String _replyBodyUnavailableText = '現在は見ることができません。';

String _commentDisplayName({
  required PublicUserProfile profile,
  required bool isOwner,
  required String authorRole,
}) {
  if (authorRole == 'teacher') {
    final displayName = _sanitizeDisplayNameForUi(
      profile.displayName,
      role: 'teacher',
      fallback: '先生',
    );
    if (displayName.isEmpty || displayName == '先生') {
      return '先生';
    }
    if (displayName.endsWith('（先生）')) {
      return displayName;
    }
    return '$displayName（先生）';
  }
  if (!isOwner) {
    return _sanitizeDisplayNameForUi(
      profile.displayName,
      role: authorRole,
      fallback: '学習者',
    );
  }
  return 'あなた';
}

String _formatCommentTimestamp(Timestamp? timestamp) {
  if (timestamp == null) {
    return '投稿直後';
  }
  final dateTime = timestamp.toDate().toLocal();
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}

bool isQuestionTeacherHiddenForViewer({
  required LessonQuestion question,
  Set<String> teacherHiddenQuestionIds = const <String>{},
}) {
  final questionId = (question.id ?? '').trim();
  final hiddenByMirror =
      questionId.isNotEmpty && teacherHiddenQuestionIds.contains(questionId);
  return question.isTeacherHidden || hiddenByMirror;
}

String _questionScopeLabel(
  LessonQuestion question, {
  bool forceTeacherHidden = false,
}) {
  final isPubliclyVisible = forceTeacherHidden
      ? false
      : question.isPubliclyVisible;
  final visibility = isPubliclyVisible ? '学習者にも公開' : '先生だけ表示';
  final learnersCanAnswer =
      isPubliclyVisible && question.target == LessonQuestionTarget.everyone;
  final answerScope = learnersCanAnswer ? '全員が回答可' : '先生だけ回答可';
  return '$visibility / $answerScope';
}

String answerScopeLabel(
  LessonQuestionAnswer answer,
  String questionScopeLabel,
) {
  if (answer.moderationStatus == lessonNoteModerationHiddenByTeacher) {
    return '先生だけ表示';
  }
  return questionScopeLabel;
}

String? answerModerationNotice(LessonQuestionAnswer answer) {
  if (answer.moderationStatus == lessonNoteModerationHiddenByTeacher) {
    return '先生によって非公開中';
  }
  return null;
}

bool canAnswerLessonQuestion({
  required LessonQuestion question,
  required String? currentUserId,
  required bool isCurrentUserTeacher,
  required bool isTeacherPreview,
}) {
  if (question.isDeleted || question.isTeacherHidden) {
    return false;
  }
  if (isTeacherPreview || isCurrentUserTeacher) {
    return true;
  }
  if (!question.isPubliclyVisible) {
    return currentUserId != null &&
        currentUserId.isNotEmpty &&
        currentUserId == question.authorId;
  }
  if (question.target == LessonQuestionTarget.everyone) {
    return true;
  }
  return currentUserId != null &&
      currentUserId.isNotEmpty &&
      currentUserId == question.authorId;
}

bool isCommentOwnerForActiveRole({
  required String? currentUserId,
  required bool isCurrentUserTeacher,
  required String authorId,
  required String authorRole,
}) {
  if (currentUserId == null || currentUserId.isEmpty) {
    return false;
  }
  if (currentUserId != authorId) {
    return false;
  }
  final currentRole = isCurrentUserTeacher ? 'teacher' : 'student';
  return authorRole == currentRole;
}

List<LessonNote> _quotableCandidateNotes(
  Iterable<LessonNote> notes, {
  required String? currentUserId,
  required bool canAccessTeacherOnlyPublicNotes,
}) {
  final safeCurrentUserId = (currentUserId ?? '').trim();
  return notes.where((note) {
    if (!note.allowsQuestionCitation || note.isDeleted) {
      return false;
    }
    if (note.isPubliclyVisible) {
      return true;
    }
    if (safeCurrentUserId.isNotEmpty && note.authorId == safeCurrentUserId) {
      return true;
    }
    return canAccessTeacherOnlyPublicNotes &&
        note.isStudentTeacherOnly &&
        !note.isTeacherHidden;
  }).toList();
}

List<LessonNote> _mergeQuotableNotes({
  required List<LessonNote> publicNotes,
  required List<LessonNote> ownNotes,
  required String currentUserId,
  required bool canAccessTeacherOnlyPublicNotes,
}) {
  final mergedById = <String, LessonNote>{};
  for (final note in publicNotes) {
    final noteId = (note.id ?? '').trim();
    if (noteId.isEmpty) {
      continue;
    }
    mergedById[noteId] = note;
  }
  for (final note in ownNotes) {
    final noteId = (note.id ?? '').trim();
    if (noteId.isEmpty) {
      continue;
    }
    mergedById[noteId] = note;
  }
  return sortLessonNotesByUpdatedAt(
    _quotableCandidateNotes(
      mergedById.values,
      currentUserId: currentUserId,
      canAccessTeacherOnlyPublicNotes: canAccessTeacherOnlyPublicNotes,
    ),
  );
}

bool canQuoteLessonNoteToPublicAudience(LessonNote? note) {
  if (note == null) {
    return true;
  }
  return note.isPubliclyVisible;
}

LessonQuestion? _initialQuestionDraftForQuotedNote(LessonNote? note) {
  if (note == null) {
    return null;
  }
  return LessonQuestion(
    authorId: '',
    authorName: '',
    courseId: note.courseId,
    courseTitle: note.courseTitle,
    lessonNumber: note.lessonNumber,
    lessonTitle: note.lessonTitle,
    title: '',
    body: '',
    visibility: LessonQuestionVisibility.teacherOnly,
    target: LessonQuestionTarget.teacher,
    attachmentTypes: const [],
    quotedNoteId: note.id,
    quotedNoteTitle: note.title,
    quotedNoteBody: note.body,
  );
}

class _ReplyLine extends StatelessWidget {
  const _ReplyLine({
    this.authorId,
    required this.displayName,
    this.linkToCurrentProfile = false,
    required this.bodyPreview,
    this.role,
  });

  final String? authorId;
  final String displayName;
  final bool linkToCurrentProfile;
  final String bodyPreview;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final fallbackDisplayName = _sanitizeDisplayNameForUi(
      displayName,
      role: role,
    );
    final safeAuthorId = (authorId ?? '').trim();
    final profileRole = role == publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    if (linkToCurrentProfile && safeAuthorId.isNotEmpty) {
      return StreamBuilder<PublicUserProfile>(
        stream: publicUserProfileStream(
          userId: safeAuthorId,
          role: profileRole,
          fallbackDisplayName: fallbackDisplayName,
        ),
        builder: (context, snapshot) {
          final profile =
              snapshot.data ??
              fallbackPublicUserProfile(
                userId: safeAuthorId,
                role: profileRole,
                displayName: fallbackDisplayName,
              );
          final linkedDisplayName = _sanitizeDisplayNameForUi(
            profile.displayName,
            role: role,
            fallback: fallbackDisplayName,
          );
          return _buildLine(context, linkedDisplayName);
        },
      );
    }
    return _buildLine(context, fallbackDisplayName);
  }

  Widget _buildLine(BuildContext context, String safeDisplayName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 2,
          height: 36,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$safeDisplayName への返信\n$bodyPreview',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ReplyTargetPreview extends StatelessWidget {
  const _ReplyTargetPreview({
    this.authorId,
    required this.displayName,
    this.linkToCurrentProfile = false,
    required this.bodyPreview,
    required this.onClear,
    this.role,
  });

  final String? authorId;
  final String displayName;
  final bool linkToCurrentProfile;
  final String bodyPreview;
  final VoidCallback onClear;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final fallbackDisplayName = _sanitizeDisplayNameForUi(
      displayName,
      role: role,
    );
    final safeAuthorId = (authorId ?? '').trim();
    final profileRole = role == publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    if (linkToCurrentProfile && safeAuthorId.isNotEmpty) {
      return StreamBuilder<PublicUserProfile>(
        stream: publicUserProfileStream(
          userId: safeAuthorId,
          role: profileRole,
          fallbackDisplayName: fallbackDisplayName,
        ),
        builder: (context, snapshot) {
          final profile =
              snapshot.data ??
              fallbackPublicUserProfile(
                userId: safeAuthorId,
                role: profileRole,
                displayName: fallbackDisplayName,
              );
          final linkedDisplayName = _sanitizeDisplayNameForUi(
            profile.displayName,
            role: role,
            fallback: fallbackDisplayName,
          );
          return _buildPreview(linkedDisplayName);
        },
      );
    }
    return _buildPreview(fallbackDisplayName);
  }

  Widget _buildPreview(String safeDisplayName) {
    return Card(
      child: ListTile(
        dense: true,
        title: Text('$safeDisplayName に返信'),
        subtitle: Text(bodyPreview),
        trailing: IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close),
          tooltip: '返信先を解除',
        ),
      ),
    );
  }
}

class _AttachmentPreviewChip extends StatelessWidget {
  const _AttachmentPreviewChip({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.insert_drive_file, size: 18),
      label: Text(label),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                _AttachmentPreviewPage(title: label, detail: detail),
          ),
        );
      },
    );
  }
}

class _QuotedNotePreviewChip extends StatelessWidget {
  const _QuotedNotePreviewChip({required this.quotedNoteId});

  final String? quotedNoteId;

  @override
  Widget build(BuildContext context) {
    final safeQuotedNoteId = (quotedNoteId ?? '').trim();
    final panel = context.findAncestorWidgetOfExactType<LessonQuestionsPanel>();
    final chip = ActionChip(
      avatar: const Icon(Icons.insert_drive_file, size: 18),
      label: const Text('レッスンメモ'),
      onPressed: () async {
        if (Firebase.apps.isNotEmpty && safeQuotedNoteId.isNotEmpty) {
          try {
            final snapshot = await FirebaseFirestore.instance
                .collection('publicLessonNotes')
                .doc(safeQuotedNoteId)
                .get();
            final data = snapshot.data();
            final note = data == null
                ? null
                : LessonNote.fromMap(data, id: snapshot.id);
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            final isOwnDeletedNote = shouldBlockOwnDeletedQuotedNoteNavigation(
              note: note,
              currentUserId: currentUserId,
            );
            if (isOwnDeletedNote) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('このメモは削除済みです。')));
              }
              return;
            }
          } catch (_) {
            // Keep current behavior when pre-check fails.
          }
        }
        if (!context.mounted) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _LatestQuotedNotePreviewPage(
              quotedNoteId: safeQuotedNoteId,
              course: panel?.course,
              lesson: panel?.lesson,
              lessonNumber: panel?.lessonNumber,
              isTeacherPreview: panel?.isTeacherPreview ?? false,
            ),
          ),
        );
      },
    );
    if (Firebase.apps.isEmpty || safeQuotedNoteId.isEmpty) {
      return chip;
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicLessonNotes')
          .doc(safeQuotedNoteId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final note = data == null
            ? null
            : LessonNote.fromMap(data, id: snapshot.data?.id);
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final canUseOwnPreview = canOpenOwnQuotedNoteDetail(
          note: note,
          currentUserId: currentUserId,
          isTeacherPreview: panel?.isTeacherPreview ?? false,
        );
        final isUnavailable = canUseOwnPreview
            ? false
            : (snapshot.data == null && !snapshot.hasError
                  ? false
                  : quotedNoteUnavailableForQuestion(
                      data,
                      exists: snapshot.data?.exists == true,
                      hasError: snapshot.hasError,
                    ));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            chip,
            if (isUnavailable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '引用元メモは削除されたか、現在は表示できません。',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LatestQuotedNotePreviewPage extends StatelessWidget {
  const _LatestQuotedNotePreviewPage({
    required this.quotedNoteId,
    this.course,
    this.lesson,
    this.lessonNumber,
    this.isTeacherPreview = false,
  });

  final String quotedNoteId;
  final Course? course;
  final CourseLesson? lesson;
  final int? lessonNumber;
  final bool isTeacherPreview;

  @override
  Widget build(BuildContext context) {
    final safeQuotedNoteId = quotedNoteId.trim();
    if (Firebase.apps.isEmpty || safeQuotedNoteId.isEmpty) {
      return const _UnavailableQuotedNotePreviewPage();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('レッスンメモ')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('publicLessonNotes')
            .doc(safeQuotedNoteId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data?.data();
          final note = data == null
              ? null
              : LessonNote.fromMap(data, id: snapshot.data?.id);
          if (note == null) {
            return const _UnavailableQuotedNotePreviewBody();
          }
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final canShowOwnDetailedPreview = canOpenOwnQuotedNoteDetail(
            note: note,
            currentUserId: currentUserId,
            isTeacherPreview: isTeacherPreview,
          );
          final hasCourseContext =
              course != null && lesson != null && lessonNumber != null;
          if (canShowOwnDetailedPreview && hasCourseContext) {
            return LessonNotePreviewBody(
              note: note,
              canCreateQuestion: note.isPubliclyVisible,
              onCreateQuestion:
                  note.isPubliclyVisible && note.allowsQuestionCitation
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('質問コメント')),
                            body: SafeArea(
                              child: LessonQuestionsPanel(
                                course: course!,
                                lesson: lesson!,
                                lessonNumber: lessonNumber!,
                                initialQuotedNote: note,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  : null,
              onEdit: (pageContext) async {
                await Navigator.of(pageContext).push(
                  MaterialPageRoute(
                    builder: (_) => LessonNotesPage(
                      course: course!,
                      lesson: lesson!,
                      lessonNumber: lessonNumber!,
                      initialFocusNoteId: note.id,
                    ),
                  ),
                );
              },
            );
          }
          final unavailable = quotedNoteUnavailableForQuestion(
            data,
            exists: snapshot.data?.exists == true,
            hasError: snapshot.hasError,
          );
          if (unavailable) {
            return const _UnavailableQuotedNotePreviewBody();
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                note.title.isEmpty ? '無題のメモ' : note.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(note.body.isEmpty ? '本文なし' : note.body),
            ],
          );
        },
      ),
    );
  }
}

class _UnavailableQuotedNotePreviewPage extends StatelessWidget {
  const _UnavailableQuotedNotePreviewPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レッスンメモ')),
      body: const _UnavailableQuotedNotePreviewBody(),
    );
  }
}

class _UnavailableQuotedNotePreviewBody extends StatelessWidget {
  const _UnavailableQuotedNotePreviewBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('引用元メモは削除されたか、現在は表示できません。'),
      ),
    );
  }
}

bool quotedNoteUnavailableForQuestion(
  Map<String, dynamic>? data, {
  required bool exists,
  required bool hasError,
}) {
  if (hasError || !exists) {
    return true;
  }
  return data?['isDeleted'] == true ||
      data?['moderationStatus'] != lessonNoteModerationVisible;
}

bool canOpenOwnQuotedNoteDetail({
  required LessonNote? note,
  required String? currentUserId,
  required bool isTeacherPreview,
}) {
  if (isTeacherPreview || note == null || note.isDeleted) {
    return false;
  }
  if (currentUserId == null || currentUserId.isEmpty) {
    return false;
  }
  return currentUserId == note.authorId;
}

bool shouldBlockOwnDeletedQuotedNoteNavigation({
  required LessonNote? note,
  required String? currentUserId,
}) {
  if (note == null || !note.isDeleted) {
    return false;
  }
  if (currentUserId == null || currentUserId.isEmpty) {
    return false;
  }
  return currentUserId == note.authorId;
}

class _AttachmentPreviewPage extends StatelessWidget {
  const _AttachmentPreviewPage({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(detail.isEmpty ? '表示できるデータはまだありません。' : detail),
      ),
    );
  }
}

String _displayNameForQuestion(LessonQuestion question) {
  if (!question.authorProfileVisible && question.authorRole != 'teacher') {
    return _sanitizeDisplayNameForUi(
      question.authorName,
      role: question.authorRole,
      fallback: '学習者',
    );
  }
  final displayName = commentIdentityFor(
    authorId: question.authorId,
    authorName: question.authorName,
    authorDisplayName: question.authorDisplayName,
    authorRole: question.authorRole,
  ).displayName;
  return _sanitizeDisplayNameForUi(
    displayName,
    role: question.authorRole,
    fallback: question.authorRole == 'teacher' ? '先生' : '学習者',
  );
}

String _displayNameForAnswer(LessonQuestionAnswer answer) {
  if (!answer.authorProfileVisible && answer.authorRole != 'teacher') {
    return _sanitizeDisplayNameForUi(
      answer.authorName,
      role: answer.authorRole,
      fallback: '学習者',
    );
  }
  final displayName = commentIdentityFor(
    authorId: answer.authorId,
    authorName: answer.authorName,
    authorDisplayName: answer.authorDisplayName,
    authorRole: answer.authorRole,
  ).displayName;
  return _sanitizeDisplayNameForUi(
    displayName,
    role: answer.authorRole,
    fallback: answer.authorRole == 'teacher' ? '先生' : '学習者',
  );
}

bool _canUseLatestQuestionReplyTargetDisplayName(LessonQuestion? question) {
  if (question == null) {
    return false;
  }
  return !question.isDeleted && !question.isTeacherHidden;
}

bool _canUseLatestAnswerReplyTargetDisplayName(LessonQuestionAnswer? answer) {
  if (answer == null) {
    return false;
  }
  if (answer.isDeleted) {
    return false;
  }
  return answer.moderationStatus != lessonInteractionModerationHiddenByTeacher;
}

String _storedReplyTargetDisplayName(String? value, {String? role}) {
  final text = (value ?? '').trim();
  if (text.isNotEmpty && !_isLikelyEmailText(text)) {
    return text;
  }
  if (role == 'teacher') {
    return '先生';
  }
  if (role == 'student') {
    return '学習者';
  }
  return '学習者';
}

class _ResolvedReplyTargetDisplay {
  const _ResolvedReplyTargetDisplay({
    required this.displayName,
    required this.linkToCurrentProfile,
  });

  final String displayName;
  final bool linkToCurrentProfile;
}

_ResolvedReplyTargetDisplay _resolvedReplyTargetDisplay({
  required LessonQuestionAnswer answer,
  LessonQuestion? parentQuestion,
  LessonQuestionAnswer? parentAnswer,
}) {
  final storedDisplayName = (answer.replyToDisplayName ?? '').trim();
  if (storedDisplayName.isEmpty || _isLikelyEmailText(storedDisplayName)) {
    return _ResolvedReplyTargetDisplay(
      displayName: _storedReplyTargetDisplayName(
        storedDisplayName,
        role: answer.replyToAuthorRole,
      ),
      linkToCurrentProfile: false,
    );
  }
  if (answer.parentCommentType == 'answer') {
    if (_canUseLatestAnswerReplyTargetDisplayName(parentAnswer)) {
      final resolved = _storedReplyTargetDisplayName(
        parentAnswer!.authorName,
        role: parentAnswer.authorRole,
      );
      return _ResolvedReplyTargetDisplay(
        displayName: resolved,
        linkToCurrentProfile:
            parentAnswer.authorRole == publicUserProfileRoleTeacher ||
            parentAnswer.authorProfileVisible,
      );
    }
  } else if (_canUseLatestQuestionReplyTargetDisplayName(parentQuestion)) {
    final resolved = _storedReplyTargetDisplayName(
      parentQuestion!.authorName,
      role: parentQuestion.authorRole,
    );
    return _ResolvedReplyTargetDisplay(
      displayName: resolved,
      linkToCurrentProfile:
          parentQuestion.authorRole == publicUserProfileRoleTeacher ||
          parentQuestion.authorProfileVisible,
    );
  }
  return _ResolvedReplyTargetDisplay(
    displayName: _storedReplyTargetDisplayName(
      answer.replyToDisplayName,
      role: answer.replyToAuthorRole,
    ),
    linkToCurrentProfile: false,
  );
}

String _replyBodyPreviewForDisplay({
  required LessonQuestionAnswer answer,
  LessonQuestion? parentQuestion,
  LessonQuestionAnswer? parentAnswer,
}) {
  final storedPreview = (answer.replyToBodyPreview ?? '').trim();
  String fallbackPreview() {
    if (storedPreview.isNotEmpty) {
      return _previewText(storedPreview);
    }
    return _replyBodyUnavailableText;
  }

  if (answer.parentCommentType == 'answer') {
    if (_canUseLatestAnswerReplyTargetDisplayName(parentAnswer)) {
      final body = parentAnswer!.body.trim();
      if (body.isEmpty) {
        return fallbackPreview();
      }
      return _previewText(body);
    }
    return fallbackPreview();
  }
  if (_canUseLatestQuestionReplyTargetDisplayName(parentQuestion)) {
    final body = parentQuestion!.body.trim();
    if (body.isEmpty) {
      return fallbackPreview();
    }
    return _previewText(body);
  }
  return fallbackPreview();
}

String _sanitizeDisplayNameForUi(
  String? value, {
  String? role,
  String fallback = '学習者',
}) {
  final text = (value ?? '').trim();
  if (text.isEmpty || _isLikelyEmailText(text)) {
    if (role == 'teacher') {
      return '先生';
    }
    if (role == 'student') {
      return '学習者';
    }
    return fallback;
  }
  return text;
}

bool _isLikelyEmailText(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return false;
  }
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
}

String _previewText(String value) {
  final normalized = value.replaceAll('\n', ' ').trim();
  if (normalized.length <= 36) {
    return normalized;
  }
  return '${normalized.substring(0, 36)}...';
}

class _QuotableNotesLoadingField extends StatelessWidget {
  const _QuotableNotesLoadingField();

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: '引用するメモ',
      ),
      child: Row(
        children: const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('引用メモを読み込み中です...'),
        ],
      ),
    );
  }
}

class _LessonQuestionDetail extends StatefulWidget {
  const _LessonQuestionDetail({
    required this.question,
    required this.answersStream,
    required this.quotableNotesStream,
    required this.initialQuotableNotes,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.canAnswer,
    required this.highlightedAnswerId,
    required this.onBack,
    required this.onSaveAnswer,
    required this.onToggleQuestionModeration,
    required this.onDeleteQuestion,
    required this.onDeleteAnswer,
    required this.onToggleAnswerModeration,
  });

  final LessonQuestion question;
  final Stream<List<LessonQuestionAnswer>> answersStream;
  final Stream<List<LessonNote>> quotableNotesStream;
  final List<LessonNote> initialQuotableNotes;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final bool canAnswer;
  final String? highlightedAnswerId;
  final VoidCallback onBack;
  final Future<bool> Function(_LessonQuestionAnswerDraft draft) onSaveAnswer;
  final Future<void> Function()? onToggleQuestionModeration;
  final Future<void> Function() onDeleteQuestion;
  final Future<void> Function(LessonQuestionAnswer answer) onDeleteAnswer;
  final Future<void> Function(LessonQuestionAnswer answer)?
  onToggleAnswerModeration;

  @override
  State<_LessonQuestionDetail> createState() => _LessonQuestionDetailState();
}

class _LessonQuestionDetailState extends State<_LessonQuestionDetail> {
  static const Duration _highlightAutoPositionWindow = Duration(seconds: 2);
  final TextEditingController _answerController = TextEditingController();
  final ScrollController _threadScrollController = ScrollController();
  final GlobalKey _highlightedAnswerBubbleKey = GlobalKey();
  String _quotedNoteId = '';
  String _quotedNoteTitle = '';
  String _quotedNoteBody = '';
  String? _replyParentId;
  String _replyParentType = 'question';
  String? _replyToAuthorId;
  String? _replyToAuthorRole;
  String? _replyToDisplayName;
  bool _replyToLinkCurrentProfile = false;
  String? _replyToBodyPreview;
  Timestamp? _replyToCreatedAt;
  String? _openedAnswerThreadRootId;
  bool _openedInitialHighlightedThread = false;
  bool _highlightAutoPositionCancelledByUser = false;
  bool _highlightAutoPositionPending = false;
  bool _applyingHighlightAutoPosition = false;
  String _lastAutoPositionSignature = '';
  DateTime? _highlightAutoPositionStartedAt;
  bool _isSaving = false;
  List<LessonQuestionAnswer> _lastNonEmptyAnswers = const [];
  String? _lastNonEmptyAnswersQuestionId;
  final Set<String> _locallyDeletedAnswerIds = <String>{};

  @override
  void initState() {
    super.initState();
    _threadScrollController.addListener(_handleThreadScrollChange);
  }

  @override
  void dispose() {
    _threadScrollController.removeListener(_handleThreadScrollChange);
    _answerController.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LessonQuestionDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _lastNonEmptyAnswers = const [];
      _lastNonEmptyAnswersQuestionId = null;
      _locallyDeletedAnswerIds.clear();
      _openedAnswerThreadRootId = null;
      _openedInitialHighlightedThread = false;
      _resetHighlightAutoPositionState();
      _scrollToTop();
    }
    if (oldWidget.highlightedAnswerId != widget.highlightedAnswerId) {
      _resetHighlightAutoPositionState();
    }
  }

  void _handleThreadScrollChange() {
    if (_applyingHighlightAutoPosition || !_threadScrollController.hasClients) {
      return;
    }
    if (_threadScrollController.position.userScrollDirection !=
        ScrollDirection.idle) {
      _highlightAutoPositionCancelledByUser = true;
    }
  }

  void _resetHighlightAutoPositionState() {
    _highlightAutoPositionCancelledByUser = false;
    _highlightAutoPositionPending = false;
    _applyingHighlightAutoPosition = false;
    _lastAutoPositionSignature = '';
    _highlightAutoPositionStartedAt = null;
  }

  String _highlightPositionSignature({
    required List<LessonQuestionAnswer> answers,
    required String? pendingAutoOpenRootId,
  }) {
    final buffer = StringBuffer();
    for (final answer in answers) {
      final id = (answer.id ?? '').trim();
      final updatedAt = timestampOrEpoch(
        answer.updatedAt,
      ).millisecondsSinceEpoch;
      buffer
        ..write(id)
        ..write(':')
        ..write(answer.parentCommentType ?? '')
        ..write(':')
        ..write(answer.parentCommentId ?? '')
        ..write(':')
        ..write(answer.moderationStatus)
        ..write(':')
        ..write(updatedAt)
        ..write('|');
    }
    buffer
      ..write('opened=')
      ..write(_openedAnswerThreadRootId ?? '')
      ..write('|pending=')
      ..write(pendingAutoOpenRootId ?? '');
    return buffer.toString();
  }

  void _scheduleHighlightedAnswerAutoPosition({required String signature}) {
    final highlightedId = (widget.highlightedAnswerId ?? '').trim();
    if (highlightedId.isEmpty ||
        _highlightAutoPositionCancelledByUser ||
        _lastAutoPositionSignature == signature ||
        _highlightAutoPositionPending) {
      return;
    }
    _highlightAutoPositionStartedAt ??= DateTime.now();
    final startedAt = _highlightAutoPositionStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > _highlightAutoPositionWindow) {
      return;
    }
    _highlightAutoPositionPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _highlightAutoPositionPending = false;
      if (!mounted || _highlightAutoPositionCancelledByUser) {
        return;
      }
      final startedAt = _highlightAutoPositionStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) > _highlightAutoPositionWindow) {
        return;
      }
      final targetContext = _highlightedAnswerBubbleKey.currentContext;
      if (targetContext == null) {
        Future<void>.delayed(const Duration(milliseconds: 50), () {
          if (!mounted) {
            return;
          }
          _scheduleHighlightedAnswerAutoPosition(signature: signature);
        });
        return;
      }
      _applyingHighlightAutoPosition = true;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0,
        duration: Duration.zero,
      );
      _applyingHighlightAutoPosition = false;
      _lastAutoPositionSignature = signature;
    });
  }

  Future<String> _resolveReplyTargetDisplayNameForSave({
    required String fallbackDisplayName,
  }) async {
    final role = _replyToAuthorRole ?? widget.question.authorRole;
    final safeFallback = _storedReplyTargetDisplayName(
      fallbackDisplayName,
      role: role,
    );
    if (!_replyToLinkCurrentProfile) {
      return safeFallback;
    }
    final safeAuthorId = (_replyToAuthorId ?? widget.question.authorId).trim();
    if (safeAuthorId.isEmpty || Firebase.apps.isEmpty) {
      return safeFallback;
    }
    final profileRole = role == publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('publicUserProfiles')
          .doc(publicUserProfileDocumentId(safeAuthorId, profileRole))
          .get();
      if (!snapshot.exists) {
        return safeFallback;
      }
      final profile = PublicUserProfile.fromFirestore(snapshot);
      return _storedReplyTargetDisplayName(profile.displayName, role: role);
    } on FirebaseException {
      return safeFallback;
    }
  }

  Future<void> _saveAnswer() async {
    if (!widget.canAnswer) {
      return;
    }
    final resolvedReplyTargetDisplayName =
        await _resolveReplyTargetDisplayNameForSave(
          fallbackDisplayName:
              _replyToDisplayName ?? _displayNameForQuestion(widget.question),
        );
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = true);
    bool saved = false;
    try {
      saved = await widget.onSaveAnswer(
        _LessonQuestionAnswerDraft(
          body: _answerController.text,
          parentCommentId: _replyParentId ?? widget.question.id,
          parentCommentType: _replyParentType,
          replyToAuthorId: _replyToAuthorId ?? widget.question.authorId,
          replyToAuthorRole: _replyToAuthorRole ?? widget.question.authorRole,
          replyToDisplayName: resolvedReplyTargetDisplayName,
          replyToBodyPreview: _replyToBodyPreview,
          replyToCreatedAt:
              _replyToCreatedAt ??
              widget.question.createdAt ??
              widget.question.updatedAt,
          quotedNoteId: _quotedNoteId.isEmpty ? null : _quotedNoteId,
          quotedNoteTitle: _quotedNoteTitle.isEmpty ? null : _quotedNoteTitle,
          quotedNoteBody: _quotedNoteBody.isEmpty ? null : _quotedNoteBody,
        ),
      );
    } finally {
      if (mounted) {
        if (saved) {
          _answerController.clear();
          _clearReplyTarget();
          _clearQuotedNoteSelection();
        }
        setState(() => _isSaving = false);
      }
    }
  }

  List<LessonQuestionAnswer> _excludeLocallyDeletedAnswers(
    List<LessonQuestionAnswer> answers,
  ) {
    if (_locallyDeletedAnswerIds.isEmpty) {
      return answers;
    }
    return answers
        .where(
          (answer) =>
              !_locallyDeletedAnswerIds.contains((answer.id ?? '').trim()),
        )
        .toList();
  }

  Future<void> _deleteAnswerWithOptimisticHide(
    LessonQuestionAnswer answer,
  ) async {
    final answerId = (answer.id ?? '').trim();
    if (answerId.isEmpty) {
      await widget.onDeleteAnswer(answer);
      return;
    }
    if (mounted) {
      setState(() {
        _locallyDeletedAnswerIds.add(answerId);
      });
    } else {
      _locallyDeletedAnswerIds.add(answerId);
    }
    try {
      await widget.onDeleteAnswer(answer);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locallyDeletedAnswerIds.remove(answerId);
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('回答コメントの削除に失敗しました。')));
    }
  }

  void _setQuestionReplyTarget() {
    if (!widget.canAnswer) {
      return;
    }
    setState(() {
      _replyParentId = widget.question.id;
      _replyParentType = 'question';
      _replyToAuthorId = widget.question.authorId;
      _replyToAuthorRole = widget.question.authorRole;
      _replyToDisplayName = _displayNameForQuestion(widget.question);
      _replyToLinkCurrentProfile =
          widget.question.authorRole == publicUserProfileRoleTeacher ||
          widget.question.authorProfileVisible;
      _replyToBodyPreview = _previewText(widget.question.body);
      _replyToCreatedAt =
          widget.question.createdAt ?? widget.question.updatedAt;
    });
  }

  void _setAnswerReplyTarget(LessonQuestionAnswer answer) {
    if (!widget.canAnswer) {
      return;
    }
    setState(() {
      _replyParentId = answer.id;
      _replyParentType = 'answer';
      _replyToAuthorId = answer.authorId;
      _replyToAuthorRole = answer.authorRole;
      _replyToDisplayName = _displayNameForAnswer(answer);
      _replyToLinkCurrentProfile =
          answer.authorRole == publicUserProfileRoleTeacher ||
          answer.authorProfileVisible;
      _replyToBodyPreview = _previewText(answer.body);
      _replyToCreatedAt = answer.createdAt ?? answer.updatedAt;
    });
  }

  void _clearReplyTarget() {
    _replyParentId = null;
    _replyParentType = 'question';
    _replyToAuthorId = null;
    _replyToAuthorRole = null;
    _replyToDisplayName = null;
    _replyToLinkCurrentProfile = false;
    _replyToBodyPreview = null;
    _replyToCreatedAt = null;
  }

  void _clearQuotedNoteSelection() {
    _quotedNoteId = '';
    _quotedNoteTitle = '';
    _quotedNoteBody = '';
  }

  void _openRepliesThread(String rootId, {bool scrollToTop = true}) {
    setState(() {
      _openedAnswerThreadRootId = rootId;
    });
    if (scrollToTop) {
      _scrollToTop();
    }
  }

  void _closeRepliesThread() {
    setState(() {
      _openedAnswerThreadRootId = null;
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_threadScrollController.hasClients) {
        return;
      }
      _threadScrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _openedAnswerThreadRootId == null
                    ? widget.onBack
                    : _closeRepliesThread,
                icon: const Icon(Icons.arrow_back),
                tooltip: _openedAnswerThreadRootId == null
                    ? '質問一覧に戻る'
                    : '質問詳細に戻る',
              ),
              Text(
                _openedAnswerThreadRootId == null ? '質問詳細' : '回答への返信',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _threadScrollController,
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<List<LessonQuestionAnswer>>(
                stream: widget.answersStream,
                builder: (context, snapshot) {
                  final incomingAnswers = _excludeLocallyDeletedAnswers(
                    snapshot.data ?? const <LessonQuestionAnswer>[],
                  );
                  final questionId = question.id;
                  final scopedIncomingAnswers = questionId == null
                      ? incomingAnswers
                      : incomingAnswers
                            .where((answer) => answer.questionId == questionId)
                            .toList();
                  if (scopedIncomingAnswers.isNotEmpty) {
                    _lastNonEmptyAnswers = scopedIncomingAnswers;
                    _lastNonEmptyAnswersQuestionId = questionId;
                  }
                  final fallbackAnswers = _excludeLocallyDeletedAnswers(
                    _lastNonEmptyAnswers,
                  );
                  final canUseFallback =
                      questionId != null &&
                      scopedIncomingAnswers.isEmpty &&
                      fallbackAnswers.isNotEmpty &&
                      _lastNonEmptyAnswersQuestionId == questionId;
                  final answers = canUseFallback
                      ? fallbackAnswers
                      : scopedIncomingAnswers;
                  final answerThreads = _buildAnswerThreads(
                    question: question,
                    answers: answers,
                  );
                  final highlightedRootId = _rootAnswerIdForHighlightedAnswer(
                    answerThreads,
                    widget.highlightedAnswerId,
                  );
                  final parentHighlightedAnswerId =
                      _parentAnswerIdForHighlightedAnswer(
                        answers,
                        widget.highlightedAnswerId,
                      );
                  final parentHighlightedQuestionId =
                      _parentQuestionIdForHighlightedAnswer(
                        answers,
                        widget.highlightedAnswerId,
                      );
                  _AnswerThread? highlightedThread;
                  if (highlightedRootId != null) {
                    for (final thread in answerThreads) {
                      if (thread.root.id == highlightedRootId) {
                        highlightedThread = thread;
                        break;
                      }
                    }
                  }
                  final shouldAutoOpenHighlightedThread =
                      highlightedThread != null &&
                      highlightedRootId != null &&
                      (widget.highlightedAnswerId != highlightedRootId ||
                          highlightedThread.replies.isNotEmpty);
                  final autoOpenRootId = shouldAutoOpenHighlightedThread
                      ? highlightedRootId
                      : null;
                  final highlightPositionSignature =
                      _highlightPositionSignature(
                        answers: answers,
                        pendingAutoOpenRootId: autoOpenRootId,
                      );
                  final standaloneHighlightedReply =
                      _standaloneHighlightedReply(
                        answers,
                        highlightedRootId,
                        widget.highlightedAnswerId,
                      );
                  if (!_openedInitialHighlightedThread &&
                      autoOpenRootId != null &&
                      _openedAnswerThreadRootId == null) {
                    _openedInitialHighlightedThread = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || _openedAnswerThreadRootId != null) {
                        return;
                      }
                      _openRepliesThread(autoOpenRootId, scrollToTop: false);
                    });
                  }
                  _scheduleHighlightedAnswerAutoPosition(
                    signature: highlightPositionSignature,
                  );
                  _AnswerThread? openedThread;
                  if (_openedAnswerThreadRootId != null) {
                    for (final thread in answerThreads) {
                      if (thread.root.id == _openedAnswerThreadRootId) {
                        openedThread = thread;
                        break;
                      }
                    }
                  }
                  Widget answersSection;
                  if (openedThread != null) {
                    answersSection = _AnswerThreadDetailView(
                      thread: openedThread,
                      parentQuestion: question,
                      scopeLabel: _questionScopeLabel(question),
                      currentUserId: widget.currentUserId,
                      isCurrentUserTeacher: widget.isCurrentUserTeacher,
                      canAnswer: widget.canAnswer,
                      onReply: _setAnswerReplyTarget,
                      onDeleteAnswer: _deleteAnswerWithOptimisticHide,
                      onToggleAnswerModeration: widget.onToggleAnswerModeration,
                      highlightedAnswerId: widget.highlightedAnswerId,
                      parentHighlightedAnswerId: parentHighlightedAnswerId,
                      highlightedBubbleKey: _highlightedAnswerBubbleKey,
                    );
                  } else if (answerThreads.isEmpty &&
                      standaloneHighlightedReply == null) {
                    answersSection = const Text('回答コメントはまだありません。');
                  } else {
                    answersSection = Column(
                      children: [
                        for (final thread in answerThreads)
                          _AnswerThreadView(
                            thread: thread,
                            parentQuestion: question,
                            scopeLabel: _questionScopeLabel(question),
                            currentUserId: widget.currentUserId,
                            isCurrentUserTeacher: widget.isCurrentUserTeacher,
                            canAnswer: widget.canAnswer,
                            onOpenReplies: thread.root.id == null
                                ? null
                                : () => _openRepliesThread(thread.root.id!),
                            onReply: _setAnswerReplyTarget,
                            onDeleteAnswer: _deleteAnswerWithOptimisticHide,
                            onToggleAnswerModeration:
                                widget.onToggleAnswerModeration,
                            highlightedAnswerId: widget.highlightedAnswerId,
                            parentHighlightedAnswerId:
                                parentHighlightedAnswerId,
                            highlightedBubbleKey: _highlightedAnswerBubbleKey,
                          ),
                        if (standaloneHighlightedReply != null)
                          _StandaloneRecordReplyView(
                            answer: standaloneHighlightedReply,
                            scopeLabel: _questionScopeLabel(question),
                            currentUserId: widget.currentUserId,
                            isCurrentUserTeacher: widget.isCurrentUserTeacher,
                            canAnswer: widget.canAnswer,
                            onReply: _setAnswerReplyTarget,
                            onDeleteAnswer: _deleteAnswerWithOptimisticHide,
                            onToggleAnswerModeration:
                                widget.onToggleAnswerModeration,
                            highlightedBubbleKey: _highlightedAnswerBubbleKey,
                          ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Offstage(
                        offstage: _openedAnswerThreadRootId != null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CommentBubble(
                              body: question.body,
                              authorId: question.authorId,
                              authorName: question.authorName,
                              authorDisplayName: question.authorDisplayName,
                              authorAvatarColorName:
                                  question.authorAvatarColorName,
                              authorProfileVisible:
                                  question.authorProfileVisible,
                              authorRole: question.authorRole,
                              postedAt: lessonQuestionPostedAt(question),
                              scopeLabel: _questionScopeLabel(question),
                              moderationNotice: question.isTeacherHidden
                                  ? '先生によって非公開中'
                                  : null,
                              attachmentTypes: question.attachmentTypes,
                              quotedNoteId: question.quotedNoteId,
                              quotedNoteTitle: question.quotedNoteTitle,
                              quotedNoteBody: question.quotedNoteBody,
                              isParentHighlighted:
                                  question.id != null &&
                                  question.id == parentHighlightedQuestionId,
                              bubbleKey:
                                  question.id != null &&
                                      question.id == parentHighlightedQuestionId
                                  ? ValueKey(
                                      'parent-highlighted-question-${question.id}',
                                    )
                                  : null,
                              isOwner: isCommentOwnerForActiveRole(
                                currentUserId: widget.currentUserId,
                                isCurrentUserTeacher:
                                    widget.isCurrentUserTeacher,
                                authorId: question.authorId,
                                authorRole: question.authorRole,
                              ),
                              isTeacher: widget.isCurrentUserTeacher,
                              onReply: widget.canAnswer
                                  ? _setQuestionReplyTarget
                                  : null,
                              onDelete:
                                  isCommentOwnerForActiveRole(
                                    currentUserId: widget.currentUserId,
                                    isCurrentUserTeacher:
                                        widget.isCurrentUserTeacher,
                                    authorId: question.authorId,
                                    authorRole: question.authorRole,
                                  )
                                  ? widget.onDeleteQuestion
                                  : null,
                              onModerate: widget.onToggleQuestionModeration,
                              moderateLabel: question.isTeacherHidden
                                  ? '公開に戻す'
                                  : '非公開にする',
                            ),
                            const Divider(height: 32),
                          ],
                        ),
                      ),
                      const Text(
                        '回答コメント',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      answersSection,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (widget.canAnswer) ...[
                if (_replyToDisplayName != null) ...[
                  _ReplyTargetPreview(
                    authorId: _replyToAuthorId,
                    displayName: _replyToDisplayName!,
                    linkToCurrentProfile: _replyToLinkCurrentProfile,
                    role: _replyToAuthorRole,
                    bodyPreview: _replyToBodyPreview ?? '',
                    onClear: () => setState(_clearReplyTarget),
                  ),
                  const SizedBox(height: 8),
                ],
                StreamBuilder<List<LessonNote>>(
                  stream: widget.quotableNotesStream,
                  initialData: widget.initialQuotableNotes.isEmpty
                      ? null
                      : widget.initialQuotableNotes,
                  builder: (context, snapshot) {
                    final isLoadingNotes =
                        !snapshot.hasData &&
                        !snapshot.hasError &&
                        snapshot.connectionState == ConnectionState.waiting;
                    final notes = snapshot.data ?? const <LessonNote>[];
                    final noteLoadErrorMessage = snapshot.hasError
                        ? '引用メモの読み込みに失敗しました。通信状態を確認して、もう一度お試しください。'
                        : null;
                    if (isLoadingNotes) {
                      return const _QuotableNotesLoadingField();
                    }
                    final selectedNoteInList =
                        _quotedNoteId.isNotEmpty &&
                        notes.any((note) => note.id == _quotedNoteId);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _quotedNoteId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '引用するメモ',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('引用なし'),
                            ),
                            if (_quotedNoteId.isNotEmpty && !selectedNoteInList)
                              DropdownMenuItem(
                                value: _quotedNoteId,
                                child: Text(
                                  _quotedNoteTitle.isEmpty
                                      ? '無題のメモ'
                                      : _quotedNoteTitle,
                                ),
                              ),
                            for (final note in notes)
                              DropdownMenuItem(
                                value: note.id ?? '',
                                child: Text(
                                  note.title.isEmpty ? '無題のメモ' : note.title,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            LessonNote? selectedNote;
                            for (final note in notes) {
                              if (note.id == value) {
                                selectedNote = note;
                                break;
                              }
                            }
                            setState(() {
                              _quotedNoteId = value ?? '';
                              _quotedNoteTitle = selectedNote?.title ?? '';
                              _quotedNoteBody = selectedNote?.body ?? '';
                            });
                          },
                        ),
                        if (noteLoadErrorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            noteLoadErrorMessage,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _answerController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '回答コメントを書く',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveAnswer,
                  icon: const Icon(Icons.reply),
                  label: const Text('回答を投稿'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AnswerThreadView extends StatelessWidget {
  const _AnswerThreadView({
    required this.thread,
    required this.parentQuestion,
    required this.scopeLabel,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.canAnswer,
    required this.onOpenReplies,
    required this.onReply,
    required this.onDeleteAnswer,
    required this.onToggleAnswerModeration,
    this.highlightedAnswerId,
    this.parentHighlightedAnswerId,
    this.highlightedBubbleKey,
  });

  final _AnswerThread thread;
  final LessonQuestion parentQuestion;
  final String scopeLabel;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final bool canAnswer;
  final VoidCallback? onOpenReplies;
  final void Function(LessonQuestionAnswer answer) onReply;
  final Future<void> Function(LessonQuestionAnswer answer) onDeleteAnswer;
  final Future<void> Function(LessonQuestionAnswer answer)?
  onToggleAnswerModeration;
  final String? highlightedAnswerId;
  final String? parentHighlightedAnswerId;
  final Key? highlightedBubbleKey;

  @override
  Widget build(BuildContext context) {
    final root = thread.root;
    final replyCount = thread.replies.length;
    final answerMap = <String, LessonQuestionAnswer>{
      for (final answer in <LessonQuestionAnswer>[root, ...thread.replies])
        if ((answer.id ?? '').trim().isNotEmpty) answer.id!.trim(): answer,
    };
    final rootParentAnswerId = (root.parentCommentId ?? '').trim();
    final rootParentAnswer = root.parentCommentType == 'answer'
        ? answerMap[rootParentAnswerId]
        : null;
    final rootReplyTarget = _resolvedReplyTargetDisplay(
      answer: root,
      parentQuestion: parentQuestion,
      parentAnswer: rootParentAnswer,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CommentBubble(
          body: root.body,
          authorId: root.authorId,
          authorName: root.authorName,
          authorDisplayName: root.authorDisplayName,
          authorAvatarColorName: root.authorAvatarColorName,
          authorProfileVisible: root.authorProfileVisible,
          authorRole: root.authorRole,
          postedAt: lessonQuestionAnswerPostedAt(root),
          scopeLabel: answerScopeLabel(root, scopeLabel),
          moderationNotice: answerModerationNotice(root),
          attachmentTypes: root.attachmentTypes,
          quotedNoteTitle: root.quotedNoteTitle,
          quotedNoteId: root.quotedNoteId,
          quotedNoteBody: root.quotedNoteBody,
          replyToAuthorId: root.replyToAuthorId,
          replyToDisplayName: rootReplyTarget.displayName,
          replyToLinkCurrentProfile: rootReplyTarget.linkToCurrentProfile,
          replyToAuthorRole: root.replyToAuthorRole,
          replyToBodyPreview: _replyBodyPreviewForDisplay(
            answer: root,
            parentQuestion: parentQuestion,
            parentAnswer: rootParentAnswer,
          ),
          isHighlighted: root.id == highlightedAnswerId,
          isParentHighlighted:
              root.id != highlightedAnswerId &&
              root.id == parentHighlightedAnswerId,
          bubbleKey: root.id == highlightedAnswerId
              ? highlightedBubbleKey
              : root.id == parentHighlightedAnswerId
              ? ValueKey('parent-highlighted-answer-${root.id}')
              : null,
          isOwner: isCommentOwnerForActiveRole(
            currentUserId: currentUserId,
            isCurrentUserTeacher: isCurrentUserTeacher,
            authorId: root.authorId,
            authorRole: root.authorRole,
          ),
          isTeacher: isCurrentUserTeacher,
          onReply: canAnswer ? () => onReply(root) : null,
          onDelete:
              isCommentOwnerForActiveRole(
                currentUserId: currentUserId,
                isCurrentUserTeacher: isCurrentUserTeacher,
                authorId: root.authorId,
                authorRole: root.authorRole,
              )
              ? () => onDeleteAnswer(root)
              : null,
          onModerate: onToggleAnswerModeration == null
              ? null
              : () => onToggleAnswerModeration!(root),
          moderateLabel:
              root.moderationStatus == lessonNoteModerationHiddenByTeacher
              ? '公開に戻す'
              : '非公開にする',
          bottomInlineAction: replyCount > 0
              ? TextButton.icon(
                  onPressed: onOpenReplies,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text('返信 $replyCount件表示'),
                )
              : null,
        ),
      ],
    );
  }
}

class _AnswerThreadDetailView extends StatelessWidget {
  const _AnswerThreadDetailView({
    required this.thread,
    required this.parentQuestion,
    required this.scopeLabel,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.canAnswer,
    required this.onReply,
    required this.onDeleteAnswer,
    required this.onToggleAnswerModeration,
    this.highlightedAnswerId,
    this.parentHighlightedAnswerId,
    this.highlightedBubbleKey,
  });

  final _AnswerThread thread;
  final LessonQuestion parentQuestion;
  final String scopeLabel;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final bool canAnswer;
  final void Function(LessonQuestionAnswer answer) onReply;
  final Future<void> Function(LessonQuestionAnswer answer) onDeleteAnswer;
  final Future<void> Function(LessonQuestionAnswer answer)?
  onToggleAnswerModeration;
  final String? highlightedAnswerId;
  final String? parentHighlightedAnswerId;
  final Key? highlightedBubbleKey;

  @override
  Widget build(BuildContext context) {
    final root = thread.root;
    final replies = thread.replies;
    final answerMap = <String, LessonQuestionAnswer>{
      for (final answer in <LessonQuestionAnswer>[root, ...replies])
        if ((answer.id ?? '').trim().isNotEmpty) answer.id!.trim(): answer,
    };
    final rootParentAnswerId = (root.parentCommentId ?? '').trim();
    final rootParentAnswer = root.parentCommentType == 'answer'
        ? answerMap[rootParentAnswerId]
        : null;
    final rootReplyTarget = _resolvedReplyTargetDisplay(
      answer: root,
      parentQuestion: parentQuestion,
      parentAnswer: rootParentAnswer,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CommentBubble(
          body: root.body,
          authorId: root.authorId,
          authorName: root.authorName,
          authorDisplayName: root.authorDisplayName,
          authorAvatarColorName: root.authorAvatarColorName,
          authorProfileVisible: root.authorProfileVisible,
          authorRole: root.authorRole,
          postedAt: lessonQuestionAnswerPostedAt(root),
          scopeLabel: answerScopeLabel(root, scopeLabel),
          moderationNotice: answerModerationNotice(root),
          attachmentTypes: root.attachmentTypes,
          quotedNoteTitle: root.quotedNoteTitle,
          quotedNoteId: root.quotedNoteId,
          quotedNoteBody: root.quotedNoteBody,
          replyToAuthorId: root.replyToAuthorId,
          replyToDisplayName: rootReplyTarget.displayName,
          replyToLinkCurrentProfile: rootReplyTarget.linkToCurrentProfile,
          replyToAuthorRole: root.replyToAuthorRole,
          replyToBodyPreview: _replyBodyPreviewForDisplay(
            answer: root,
            parentQuestion: parentQuestion,
            parentAnswer: rootParentAnswer,
          ),
          isHighlighted: root.id == highlightedAnswerId,
          isParentHighlighted:
              root.id != highlightedAnswerId &&
              root.id == parentHighlightedAnswerId,
          bubbleKey: root.id == highlightedAnswerId
              ? highlightedBubbleKey
              : root.id == parentHighlightedAnswerId
              ? ValueKey('parent-highlighted-answer-${root.id}')
              : null,
          isOwner: isCommentOwnerForActiveRole(
            currentUserId: currentUserId,
            isCurrentUserTeacher: isCurrentUserTeacher,
            authorId: root.authorId,
            authorRole: root.authorRole,
          ),
          isTeacher: isCurrentUserTeacher,
          onReply: canAnswer ? () => onReply(root) : null,
          onDelete:
              isCommentOwnerForActiveRole(
                currentUserId: currentUserId,
                isCurrentUserTeacher: isCurrentUserTeacher,
                authorId: root.authorId,
                authorRole: root.authorRole,
              )
              ? () => onDeleteAnswer(root)
              : null,
          onModerate: onToggleAnswerModeration == null
              ? null
              : () => onToggleAnswerModeration!(root),
          moderateLabel:
              root.moderationStatus == lessonNoteModerationHiddenByTeacher
              ? '公開に戻す'
              : '非公開にする',
        ),
        const SizedBox(height: 4),
        if (replies.isEmpty)
          const Text('返信はまだありません。')
        else
          Column(
            children: [
              for (final reply in replies)
                Builder(
                  builder: (context) {
                    final replyTarget = _resolvedReplyTargetDisplay(
                      answer: reply,
                      parentQuestion: parentQuestion,
                      parentAnswer: reply.parentCommentType == 'answer'
                          ? answerMap[(reply.parentCommentId ?? '').trim()]
                          : null,
                    );
                    return _CommentBubble(
                      body: reply.body,
                      authorId: reply.authorId,
                      authorName: reply.authorName,
                      authorDisplayName: reply.authorDisplayName,
                      authorAvatarColorName: reply.authorAvatarColorName,
                      authorProfileVisible: reply.authorProfileVisible,
                      authorRole: reply.authorRole,
                      postedAt: lessonQuestionAnswerPostedAt(reply),
                      scopeLabel: answerScopeLabel(reply, scopeLabel),
                      moderationNotice: answerModerationNotice(reply),
                      attachmentTypes: reply.attachmentTypes,
                      quotedNoteTitle: reply.quotedNoteTitle,
                      quotedNoteId: reply.quotedNoteId,
                      quotedNoteBody: reply.quotedNoteBody,
                      replyToAuthorId: reply.replyToAuthorId,
                      replyToDisplayName: replyTarget.displayName,
                      replyToLinkCurrentProfile:
                          replyTarget.linkToCurrentProfile,
                      replyToAuthorRole: reply.replyToAuthorRole,
                      replyToBodyPreview: _replyBodyPreviewForDisplay(
                        answer: reply,
                        parentQuestion: parentQuestion,
                        parentAnswer: reply.parentCommentType == 'answer'
                            ? answerMap[(reply.parentCommentId ?? '').trim()]
                            : null,
                      ),
                      isHighlighted: reply.id == highlightedAnswerId,
                      isParentHighlighted:
                          reply.id != highlightedAnswerId &&
                          reply.id == parentHighlightedAnswerId,
                      bubbleKey: reply.id == highlightedAnswerId
                          ? highlightedBubbleKey
                          : reply.id == parentHighlightedAnswerId
                          ? ValueKey('parent-highlighted-answer-${reply.id}')
                          : null,
                      isOwner: isCommentOwnerForActiveRole(
                        currentUserId: currentUserId,
                        isCurrentUserTeacher: isCurrentUserTeacher,
                        authorId: reply.authorId,
                        authorRole: reply.authorRole,
                      ),
                      isTeacher: isCurrentUserTeacher,
                      onReply: canAnswer ? () => onReply(reply) : null,
                      onDelete:
                          isCommentOwnerForActiveRole(
                            currentUserId: currentUserId,
                            isCurrentUserTeacher: isCurrentUserTeacher,
                            authorId: reply.authorId,
                            authorRole: reply.authorRole,
                          )
                          ? () => onDeleteAnswer(reply)
                          : null,
                      onModerate: onToggleAnswerModeration == null
                          ? null
                          : () => onToggleAnswerModeration!(reply),
                      moderateLabel:
                          reply.moderationStatus ==
                              lessonNoteModerationHiddenByTeacher
                          ? '公開に戻す'
                          : '非公開にする',
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _StandaloneRecordReplyView extends StatelessWidget {
  const _StandaloneRecordReplyView({
    required this.answer,
    required this.scopeLabel,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.canAnswer,
    required this.onReply,
    required this.onDeleteAnswer,
    required this.onToggleAnswerModeration,
    this.highlightedBubbleKey,
  });

  final LessonQuestionAnswer answer;
  final String scopeLabel;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final bool canAnswer;
  final void Function(LessonQuestionAnswer answer) onReply;
  final Future<void> Function(LessonQuestionAnswer answer) onDeleteAnswer;
  final Future<void> Function(LessonQuestionAnswer answer)?
  onToggleAnswerModeration;
  final Key? highlightedBubbleKey;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'この記録の返信',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '返信先の回答は削除済み、または現在は表示できません。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _CommentBubble(
              body: answer.body,
              authorId: answer.authorId,
              authorName: answer.authorName,
              authorDisplayName: answer.authorDisplayName,
              authorAvatarColorName: answer.authorAvatarColorName,
              authorProfileVisible: answer.authorProfileVisible,
              authorRole: answer.authorRole,
              postedAt: lessonQuestionAnswerPostedAt(answer),
              scopeLabel: answerScopeLabel(answer, scopeLabel),
              moderationNotice: answerModerationNotice(answer),
              attachmentTypes: answer.attachmentTypes,
              quotedNoteTitle: answer.quotedNoteTitle,
              quotedNoteId: answer.quotedNoteId,
              quotedNoteBody: answer.quotedNoteBody,
              replyToAuthorId: answer.replyToAuthorId,
              replyToDisplayName: _storedReplyTargetDisplayName(
                answer.replyToDisplayName,
                role: answer.replyToAuthorRole,
              ),
              replyToAuthorRole: answer.replyToAuthorRole,
              replyToBodyPreview: _replyBodyUnavailableText,
              isHighlighted: true,
              bubbleKey: highlightedBubbleKey,
              isOwner: isCommentOwnerForActiveRole(
                currentUserId: currentUserId,
                isCurrentUserTeacher: isCurrentUserTeacher,
                authorId: answer.authorId,
                authorRole: answer.authorRole,
              ),
              isTeacher: isCurrentUserTeacher,
              onReply: canAnswer ? () => onReply(answer) : null,
              onDelete:
                  isCommentOwnerForActiveRole(
                    currentUserId: currentUserId,
                    isCurrentUserTeacher: isCurrentUserTeacher,
                    authorId: answer.authorId,
                    authorRole: answer.authorRole,
                  )
                  ? () => onDeleteAnswer(answer)
                  : null,
              onModerate: onToggleAnswerModeration == null
                  ? null
                  : () => onToggleAnswerModeration!(answer),
              moderateLabel:
                  answer.moderationStatus == lessonNoteModerationHiddenByTeacher
                  ? '公開に戻す'
                  : '非公開にする',
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerThread {
  const _AnswerThread({required this.root, required this.replies});

  final LessonQuestionAnswer root;
  final List<LessonQuestionAnswer> replies;
}

LessonQuestionAnswer? _standaloneHighlightedReply(
  List<LessonQuestionAnswer> answers,
  String? highlightedRootId,
  String? highlightedAnswerId,
) {
  if (highlightedRootId != null ||
      highlightedAnswerId == null ||
      highlightedAnswerId.isEmpty) {
    return null;
  }
  for (final answer in answers) {
    if (answer.id == highlightedAnswerId &&
        answer.parentCommentType == 'answer') {
      return answer;
    }
  }
  return null;
}

String? _rootAnswerIdForHighlightedAnswer(
  List<_AnswerThread> threads,
  String? highlightedAnswerId,
) {
  if (highlightedAnswerId == null || highlightedAnswerId.isEmpty) {
    return null;
  }
  for (final thread in threads) {
    if (thread.root.id == highlightedAnswerId) {
      return thread.root.id;
    }
    for (final reply in thread.replies) {
      if (reply.id == highlightedAnswerId) {
        return thread.root.id;
      }
    }
  }
  return null;
}

String? _parentAnswerIdForHighlightedAnswer(
  List<LessonQuestionAnswer> answers,
  String? highlightedAnswerId,
) {
  if (highlightedAnswerId == null || highlightedAnswerId.isEmpty) {
    return null;
  }
  for (final answer in answers) {
    if (answer.id != highlightedAnswerId) {
      continue;
    }
    if (answer.parentCommentType != 'answer') {
      return null;
    }
    final parentId = answer.parentCommentId;
    if (parentId == null || parentId.isEmpty) {
      return null;
    }
    return parentId;
  }
  return null;
}

String? _parentQuestionIdForHighlightedAnswer(
  List<LessonQuestionAnswer> answers,
  String? highlightedAnswerId,
) {
  if (highlightedAnswerId == null || highlightedAnswerId.isEmpty) {
    return null;
  }
  for (final answer in answers) {
    if (answer.id != highlightedAnswerId) {
      continue;
    }
    if (answer.parentCommentType == 'answer') {
      return null;
    }
    final parentId = answer.parentCommentId;
    if (parentId == null || parentId.isEmpty) {
      return answer.questionId.isEmpty ? null : answer.questionId;
    }
    return parentId;
  }
  return null;
}

List<_AnswerThread> _buildAnswerThreads({
  required LessonQuestion question,
  required List<LessonQuestionAnswer> answers,
}) {
  final answersById = {
    for (final answer in answers)
      if (answer.id != null) answer.id!: answer,
  };
  final directAnswers = answers
      .where((answer) => _isDirectAnswerToQuestion(answer, question))
      .toList();
  final repliesByRootId = <String, List<LessonQuestionAnswer>>{};

  for (final answer in answers) {
    if (_isDirectAnswerToQuestion(answer, question)) {
      continue;
    }
    final rootId = _rootAnswerIdFor(
      answer: answer,
      question: question,
      answersById: answersById,
    );
    if (rootId == null) {
      continue;
    }
    repliesByRootId.putIfAbsent(rootId, () => []).add(answer);
  }

  return [
    for (final root in directAnswers)
      _AnswerThread(root: root, replies: repliesByRootId[root.id] ?? const []),
  ];
}

bool _isDirectAnswerToQuestion(
  LessonQuestionAnswer answer,
  LessonQuestion question,
) {
  if (answer.parentCommentType == 'answer') {
    return false;
  }
  return answer.parentCommentId == null ||
      answer.parentCommentId == question.id ||
      answer.parentCommentType == 'question';
}

String? _rootAnswerIdFor({
  required LessonQuestionAnswer answer,
  required LessonQuestion question,
  required Map<String, LessonQuestionAnswer> answersById,
}) {
  final explicitRootId = (answer.threadRootAnswerId ?? '').trim();
  if (explicitRootId.isNotEmpty) {
    final explicitRoot = answersById[explicitRootId];
    if (explicitRoot == null ||
        !_isDirectAnswerToQuestion(explicitRoot, question)) {
      return null;
    }
    return explicitRootId;
  }
  var current = answer;
  final visitedIds = <String>{};
  while (true) {
    if (_isDirectAnswerToQuestion(current, question)) {
      return current.id;
    }
    final parentId = current.parentCommentId;
    if (parentId == null || !visitedIds.add(parentId)) {
      return null;
    }
    final parent = answersById[parentId];
    if (parent == null) {
      return null;
    }
    current = parent;
  }
}

class _LessonQuestionEditor extends StatefulWidget {
  const _LessonQuestionEditor({
    required this.question,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.onCancel,
    required this.onSave,
    required this.quotableNotesStream,
    required this.initialQuotableNotes,
    this.initialQuotedNote,
  });

  final LessonQuestion? question;
  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final VoidCallback onCancel;
  final Future<bool> Function(_LessonQuestionDraft draft) onSave;
  final Stream<List<LessonNote>> quotableNotesStream;
  final List<LessonNote> initialQuotableNotes;
  final LessonNote? initialQuotedNote;

  @override
  State<_LessonQuestionEditor> createState() => _LessonQuestionEditorState();
}

class _LessonQuestionEditorState extends State<_LessonQuestionEditor> {
  late final TextEditingController _bodyController;
  LessonQuestionVisibility _visibility = LessonQuestionVisibility.teacherOnly;
  LessonQuestionTarget _target = LessonQuestionTarget.teacher;
  String _quotedNoteId = '';
  String _quotedNoteTitle = '';
  String _quotedNoteBody = '';
  final Set<String> _attachmentTypes = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    _bodyController = TextEditingController(text: question?.body ?? '');
    _visibility = question?.visibility ?? LessonQuestionVisibility.teacherOnly;
    _target = question?.target ?? LessonQuestionTarget.teacher;
    _quotedNoteId = question?.quotedNoteId ?? '';
    _quotedNoteTitle = question?.quotedNoteTitle ?? '';
    _quotedNoteBody = question?.quotedNoteBody ?? '';
    _attachmentTypes.addAll(question?.attachmentTypes ?? const []);
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.question?.id != null;

  List<LessonNote> _notesWithInitialQuotedNote(List<LessonNote> notes) {
    final initialNote = widget.initialQuotedNote;
    if (initialNote == null) {
      return notes;
    }
    final initialNoteId = initialNote.id;
    if (initialNoteId == null || _quotedNoteId != initialNoteId) {
      return notes;
    }
    for (final note in notes) {
      if (note.id == initialNoteId) {
        return notes;
      }
    }
    return [initialNote, ...notes];
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final saved = await widget.onSave(
      _LessonQuestionDraft(
        questionId: widget.question?.id,
        body: _bodyController.text.trim(),
        visibility: _visibility,
        target: _target,
        attachmentTypes: _attachmentTypes.toList()..sort(),
        quotedNoteId: _quotedNoteId.isEmpty ? null : _quotedNoteId,
        quotedNoteTitle: _quotedNoteTitle.isEmpty ? null : _quotedNoteTitle,
        quotedNoteBody: _quotedNoteBody.isEmpty ? null : _quotedNoteBody,
        wasPublic: widget.question?.isPublic ?? false,
      ),
    );
    if (mounted) {
      setState(() => _isSaving = false);
    }
    if (!saved) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _isEditing;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.arrow_back),
                tooltip: '質問一覧に戻る',
              ),
              Text(
                widget.question?.id == null ? '質問を作成' : '質問を編集',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.course.title} / レッスン${widget.lessonNumber}: ${widget.lesson.title}',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bodyController,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '質問本文',
                ),
              ),
              const SizedBox(height: 12),
              if (isEditing) ...[
                _LockedQuestionSettings(
                  visibility: _visibility,
                  target: _target,
                ),
              ] else ...[
                SegmentedButton<LessonQuestionTarget>(
                  segments: const [
                    ButtonSegment(
                      value: LessonQuestionTarget.teacher,
                      label: Text('先生に質問'),
                    ),
                    ButtonSegment(
                      value: LessonQuestionTarget.everyone,
                      label: Text('全員に質問'),
                    ),
                  ],
                  selected: {_target},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _target = selection.first;
                      if (_target == LessonQuestionTarget.everyone) {
                        _visibility = LessonQuestionVisibility.public;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('他の学習者にも公開する'),
                  subtitle: const Text('オフの場合は先生にだけ公開されます。'),
                  value: _visibility == LessonQuestionVisibility.public,
                  onChanged: _target == LessonQuestionTarget.everyone
                      ? null
                      : (value) {
                          setState(() {
                            _visibility = value
                                ? LessonQuestionVisibility.public
                                : LessonQuestionVisibility.teacherOnly;
                          });
                        },
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<LessonNote>>(
                  stream: widget.quotableNotesStream,
                  initialData: widget.initialQuotableNotes.isEmpty
                      ? null
                      : widget.initialQuotableNotes,
                  builder: (context, snapshot) {
                    final isLoadingNotes =
                        !snapshot.hasData &&
                        !snapshot.hasError &&
                        snapshot.connectionState == ConnectionState.waiting;
                    final notes = _notesWithInitialQuotedNote(
                      snapshot.data ?? const <LessonNote>[],
                    );
                    final noteLoadErrorMessage = snapshot.hasError
                        ? '引用メモの読み込みに失敗しました。通信状態を確認して、もう一度お試しください。'
                        : null;
                    if (isLoadingNotes) {
                      return const _QuotableNotesLoadingField();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _quotedNoteId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '引用するメモ',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('引用なし'),
                            ),
                            for (final note in notes)
                              DropdownMenuItem(
                                value: note.id ?? '',
                                child: Text(
                                  note.title.isEmpty ? '無題のメモ' : note.title,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            LessonNote? selectedNote;
                            for (final note in notes) {
                              if (note.id == value) {
                                selectedNote = note;
                                break;
                              }
                            }
                            setState(() {
                              _quotedNoteId = value ?? '';
                              _quotedNoteTitle = selectedNote?.title ?? '';
                              _quotedNoteBody = selectedNote?.body ?? '';
                            });
                          },
                        ),
                        if (noteLoadErrorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            noteLoadErrorMessage,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text('添付予定タイプ'),
                Wrap(
                  spacing: 8,
                  children: [
                    _QuestionAttachmentChip(
                      label: 'PDF',
                      value: lessonNoteAttachmentPdf,
                      selected: _attachmentTypes.contains(
                        lessonNoteAttachmentPdf,
                      ),
                      onSelected: _toggleAttachment,
                    ),
                    _QuestionAttachmentChip(
                      label: '画像',
                      value: lessonNoteAttachmentImage,
                      selected: _attachmentTypes.contains(
                        lessonNoteAttachmentImage,
                      ),
                      onSelected: _toggleAttachment,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: Icon(
                  widget.question?.id == null ? Icons.send : Icons.save,
                ),
                label: Text(widget.question?.id == null ? 'コメントを投稿' : '変更を保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleAttachment(String value, bool selected) {
    setState(() {
      if (selected) {
        _attachmentTypes.add(value);
      } else {
        _attachmentTypes.remove(value);
      }
    });
  }
}

class _LockedQuestionSettings extends StatelessWidget {
  const _LockedQuestionSettings({
    required this.visibility,
    required this.target,
  });

  final LessonQuestionVisibility visibility;
  final LessonQuestionTarget target;

  @override
  Widget build(BuildContext context) {
    final visibilityText = visibility == LessonQuestionVisibility.public
        ? '学習者にも公開'
        : '先生だけ表示';
    final targetText = target == LessonQuestionTarget.everyone
        ? '全員に質問'
        : '先生に質問';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '公開範囲と宛先は投稿後に変更できません。',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('公開範囲: $visibilityText'),
            Text('宛先: $targetText'),
          ],
        ),
      ),
    );
  }
}

class _QuestionAttachmentChip extends StatelessWidget {
  const _QuestionAttachmentChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool selected;
  final void Function(String value, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (selected) => onSelected(value, selected),
    );
  }
}

class _LessonQuestionDraft {
  const _LessonQuestionDraft({
    required this.questionId,
    required this.body,
    required this.visibility,
    required this.target,
    required this.attachmentTypes,
    required this.quotedNoteId,
    required this.quotedNoteTitle,
    required this.quotedNoteBody,
    required this.wasPublic,
  });

  final String? questionId;
  final String body;
  final LessonQuestionVisibility visibility;
  final LessonQuestionTarget target;
  final List<String> attachmentTypes;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
  final bool wasPublic;
}

class _LessonQuestionAnswerDraft {
  const _LessonQuestionAnswerDraft({
    required this.body,
    required this.parentCommentId,
    required this.parentCommentType,
    required this.replyToAuthorId,
    required this.replyToAuthorRole,
    required this.replyToDisplayName,
    required this.replyToBodyPreview,
    required this.replyToCreatedAt,
    required this.quotedNoteId,
    required this.quotedNoteTitle,
    required this.quotedNoteBody,
  });

  final String body;
  final String? parentCommentId;
  final String parentCommentType;
  final String? replyToAuthorId;
  final String? replyToAuthorRole;
  final String? replyToDisplayName;
  final String? replyToBodyPreview;
  final Timestamp? replyToCreatedAt;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
}
