import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_config.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_playback_mode.dart';
import '../models/lesson_publication_validator.dart';
import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/course_lesson_repository.dart';
import '../services/lesson_media_duration_service.dart';
import '../services/lesson_media_storage_service.dart';
import '../utils/firebase_error_message.dart';
import '../widgets/lesson_whiteboard_editor_panel.dart';
import 'teacher_quiz_manage_page.dart';

typedef LessonSaveOverride = Future<void> Function(List<CourseLesson> lessons);
typedef LessonDraftSaveOverride =
    Future<void> Function({
      required int lessonNumber,
      required BoardSet boardSet,
      required int expectedLessonContentVersion,
    });
typedef VersionedLessonDraftSaveOverride =
    Future<int> Function({
      required int lessonNumber,
      required BoardSet boardSet,
      required int expectedLessonContentVersion,
      required int expectedDraftRevision,
    });

const String lessonCountConflictMessage =
    '保存済みレッスンの件数が変わりました。画面を読み込み直してから再度お試しください。';

({BoardSet boardSet, int draftRevision})? matchingLessonDraft(
  Map<String, dynamic>? data, {
  required int lessonContentVersion,
  int? expectedDraftRevision,
}) {
  if (data == null ||
      data['baseLessonContentVersion'] != lessonContentVersion ||
      data['draftRevision'] is! int ||
      (data['draftRevision'] as int) < 1 ||
      (data['draftRevision'] as int) > 2147483647 ||
      (expectedDraftRevision != null &&
          data['draftRevision'] != expectedDraftRevision) ||
      data['boardSet'] is! Map) {
    return null;
  }
  return (
    boardSet: BoardSet.fromMap(data['boardSet']),
    draftRevision: data['draftRevision'] as int,
  );
}

({BoardSet boardSet, int draftRevision})? lessonDraftForPublication(
  Map<String, dynamic>? data, {
  required int lessonContentVersion,
  required int expectedDraftRevision,
}) {
  if (data == null) {
    if (expectedDraftRevision == 0) {
      return null;
    }
    throw const LessonPublicationValidationException(
      lessonDraftRevisionConflictMessage,
    );
  }
  final matchingDraft = matchingLessonDraft(
    data,
    lessonContentVersion: lessonContentVersion,
    expectedDraftRevision: expectedDraftRevision,
  );
  if (matchingDraft == null) {
    throw const LessonPublicationValidationException(
      lessonDraftRevisionConflictMessage,
    );
  }
  return matchingDraft;
}

List<CourseLesson> overlayLessonDraftBoardSets(
  List<CourseLesson> lessons,
  Map<int, BoardSet> draftBoardSetsByLessonNumber,
) {
  return [
    for (final entry in lessons.indexed)
      draftBoardSetsByLessonNumber.containsKey(entry.$1 + 1)
          ? entry.$2.copyWith(
              draftBoardSet: draftBoardSetsByLessonNumber[entry.$1 + 1]!,
            )
          : entry.$2,
  ];
}

List<CourseLesson> promoteLessonDraftBoardSets(
  List<CourseLesson> lessons,
  Map<int, BoardSet> draftBoardSetsByLessonNumber,
) {
  return [
    for (final entry in lessons.indexed)
      draftBoardSetsByLessonNumber.containsKey(entry.$1 + 1)
          ? entry.$2.copyWith(
              publishedBoardSet: draftBoardSetsByLessonNumber[entry.$1 + 1]!,
              clearDraftBoardSet: true,
            )
          : entry.$2,
  ];
}

List<CourseLesson> retainPersistedLessonBoardSets({
  required List<CourseLesson> latestLessons,
  required List<CourseLesson> editedLessons,
}) {
  return [
    for (var index = 0; index < editedLessons.length; index++)
      editedLessons[index].copyWith(
        publishedBoardSet: latestLessons[index].draftBoardSet.isNotEmpty
            ? latestLessons[index].draftBoardSet
            : latestLessons[index].publishedBoardSet,
        clearDraftBoardSet: true,
      ),
  ];
}

String _playbackModeExplanation(LessonPlaybackMode mode) {
  return switch (mode) {
    LessonPlaybackMode.continuous => 'すべてのパートを順番に一貫して再生します。',
    LessonPlaybackMode.independentSingle => '選んだパートを同じ再生画面で個別に再生します。',
    LessonPlaybackMode.independentPanels => '各パートをそれぞれ独立した画面で再生します。',
  };
}

List<CourseLesson> _prepareLessonsForPublication({
  required List<CourseLesson> previousLessons,
  required List<CourseLesson> nextLessons,
}) {
  if (previousLessons.length != nextLessons.length) {
    throw const LessonPublicationValidationException(
      lessonCountConflictMessage,
    );
  }
  final publishedLessons = [
    for (var index = 0; index < nextLessons.length; index++)
      LessonPublicationValidator.prepareForPublication(
        previous: previousLessons[index],
        next: nextLessons[index],
      ),
  ];
  validateLessonBoardSetsForPersistence(publishedLessons);
  return publishedLessons;
}

class _LessonSaveResult {
  const _LessonSaveResult({
    required this.lessons,
    required this.previousLessons,
    required this.lessonContentVersion,
  });

  final List<CourseLesson> lessons;
  final List<CourseLesson> previousLessons;
  final int lessonContentVersion;
}

class _LoadedLessonData {
  const _LoadedLessonData({
    required this.course,
    required this.draftBoardSets,
    required this.draftRevisions,
  });

  final Course course;
  final Map<int, BoardSet> draftBoardSets;
  final Map<int, int> draftRevisions;
}

class TeacherLessonManagePage extends StatefulWidget {
  const TeacherLessonManagePage({
    super.key,
    required this.course,
    this.lessonId,
    this.onSaveOverride,
    this.onLessonDraftSaveOverride,
    this.onVersionedLessonDraftSaveOverride,
    this.initialLessonDrafts = const {},
    this.initialLessonDraftRevisions = const {},
    this.mediaStorageService = const LessonMediaStorageService(),
    this.durationService = const LessonMediaDurationService(),
  });

  final Course course;
  final String? lessonId;
  final LessonSaveOverride? onSaveOverride;
  final LessonDraftSaveOverride? onLessonDraftSaveOverride;
  final VersionedLessonDraftSaveOverride? onVersionedLessonDraftSaveOverride;
  final Map<int, BoardSet> initialLessonDrafts;
  final Map<int, int> initialLessonDraftRevisions;
  final LessonMediaStorageService mediaStorageService;
  final LessonMediaDurationService durationService;

  @override
  State<TeacherLessonManagePage> createState() =>
      _TeacherLessonManagePageState();
}

class _TeacherLessonManagePageState extends State<TeacherLessonManagePage> {
  static const _mediaConfig = LessonMediaConfig.current;
  final _lessonRepository = const CourseLessonRepository();

  late List<_LessonEditorState> _lessonEditors;
  late Course _activeCourse;
  late List<CourseLesson> _lastPersistedLessons;
  late int _loadedLessonContentVersion;
  late Map<int, int> _loadedDraftRevisions;
  late int _selectedLessonNumber;
  bool _isSaving = false;
  bool _isLoadingLessons = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _activeCourse = widget.course;
    _loadedLessonContentVersion = widget.course.lessonContentVersion;
    _loadedDraftRevisions = Map<int, int>.from(
      widget.initialLessonDraftRevisions,
    );
    final initialLessons = overlayLessonDraftBoardSets(
      _activeCourse.lessons,
      widget.initialLessonDrafts,
    );
    final selectedIndex = widget.lessonId == null
        ? -1
        : initialLessons.indexWhere((lesson) => lesson.id == widget.lessonId);
    _selectedLessonNumber = selectedIndex < 0 ? 1 : selectedIndex + 1;
    final editableLessons = widget.lessonId == null
        ? initialLessons
        : selectedIndex < 0
        ? const <CourseLesson>[]
        : <CourseLesson>[initialLessons[selectedIndex]];
    _lessonEditors = editableLessons
        .map(_LessonEditorState.fromLesson)
        .toList();
    _lastPersistedLessons = editableLessons;
    if (editableLessons.isNotEmpty && widget.lessonId != null) {
      _loadedLessonContentVersion = editableLessons.single.documentVersion;
    }
    unawaited(_loadLatestLessons());
  }

  @override
  void dispose() {
    widget.mediaStorageService.cancelActiveFilePicker();
    for (final editor in _lessonEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLatestLessons() async {
    final courseId = widget.course.id;
    if (courseId == null || widget.onSaveOverride != null) {
      return;
    }

    if (widget.lessonId != null) {
      await _loadSelectedLesson(courseId);
      return;
    }

    setState(() {
      _isLoadingLessons = true;
    });

    try {
      final courseReference = FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId);
      final loaded = await FirebaseFirestore.instance
          .runTransaction<_LoadedLessonData?>((transaction) async {
            final snapshot = await transaction.get(courseReference);
            if (!snapshot.exists) {
              return null;
            }
            final latestCourse = Course.fromFirestore(snapshot);
            final draftBoardSets = <int, BoardSet>{};
            final draftRevisions = <int, int>{};
            for (
              var lessonNumber = 1;
              lessonNumber <= latestCourse.lessons.length;
              lessonNumber++
            ) {
              final draftSnapshot = await transaction.get(
                courseReference.collection('lessonDrafts').doc('$lessonNumber'),
              );
              final matchingDraft = matchingLessonDraft(
                draftSnapshot.data(),
                lessonContentVersion: latestCourse.lessonContentVersion,
              );
              if (matchingDraft != null) {
                draftBoardSets[lessonNumber] = matchingDraft.boardSet;
                draftRevisions[lessonNumber] = matchingDraft.draftRevision;
              }
            }
            return _LoadedLessonData(
              course: latestCourse,
              draftBoardSets: draftBoardSets,
              draftRevisions: draftRevisions,
            );
          });
      if (!mounted || loaded == null) {
        return;
      }

      final latestCourse = loaded.course;
      final lessonsWithDrafts = overlayLessonDraftBoardSets(
        latestCourse.lessons,
        loaded.draftBoardSets,
      );
      setState(() {
        _activeCourse = latestCourse;
        _loadedLessonContentVersion = latestCourse.lessonContentVersion;
        _loadedDraftRevisions = loaded.draftRevisions;
        _lastPersistedLessons = lessonsWithDrafts;
        for (final editor in _lessonEditors) {
          editor.dispose();
        }
        _lessonEditors = lessonsWithDrafts
            .map(_LessonEditorState.fromLesson)
            .toList();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '保存済みレッスン情報の読み込みに失敗しました。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLessons = false;
        });
      }
    }
  }

  Future<void> _loadSelectedLesson(String courseId) async {
    setState(() {
      _isLoadingLessons = true;
    });
    try {
      final lesson = await _lessonRepository.fetchLesson(
        courseId: courseId,
        lessonId: widget.lessonId!,
      );
      if (lesson == null) {
        throw StateError('レッスンが見つかりません。');
      }
      final draftSnapshot = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .collection('lessonDrafts')
          .doc(widget.lessonId)
          .get();
      final draftData = draftSnapshot.data();
      BoardSet? draftBoardSet;
      var draftRevision = 0;
      if (draftData != null &&
          draftData['baseLessonDocumentVersion'] == lesson.documentVersion &&
          draftData['draftRevision'] is int &&
          draftData['boardSet'] is Map) {
        draftBoardSet = BoardSet.fromMap(draftData['boardSet']);
        draftRevision = draftData['draftRevision'] as int;
      }
      final lessonWithDraft = draftBoardSet == null
          ? lesson
          : lesson.copyWith(draftBoardSet: draftBoardSet);
      if (!mounted) {
        return;
      }
      setState(() {
        for (final editor in _lessonEditors) {
          editor.dispose();
        }
        _lessonEditors = [_LessonEditorState.fromLesson(lessonWithDraft)];
        _lastPersistedLessons = [lessonWithDraft];
        _loadedLessonContentVersion = lesson.documentVersion;
        _loadedDraftRevisions = {
          if (draftRevision > 0) _selectedLessonNumber: draftRevision,
        };
        _activeCourse = _replaceLessonInCourse(_activeCourse, lessonWithDraft);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '保存済みレッスン情報の読み込みに失敗しました。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLessons = false;
        });
      }
    }
  }

  Course _replaceLessonInCourse(Course course, CourseLesson lesson) {
    final lessons = [...course.lessons];
    final index = lessons.indexWhere((item) => item.id == lesson.id);
    if (index >= 0) {
      lessons[index] = lesson;
    } else {
      lessons.add(lesson);
    }
    return course.withLessonContent(sortCourseLessons(lessons));
  }

  int _lessonNumberForEditor(int editorIndex) {
    return widget.lessonId == null ? editorIndex + 1 : _selectedLessonNumber;
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '入力してください';
    }
    return null;
  }

  List<CourseLesson>? _buildLessons() {
    final lessons = <CourseLesson>[];

    for (final entry in _lessonEditors.indexed) {
      final editor = entry.$2;
      final title = editor.titleController.text.trim();
      if (title.isEmpty) {
        setState(() {
          _message = 'レッスンタイトルを入力してください。';
        });
        return null;
      }

      final durationLabel = editor.durationController.text.trim().isEmpty
          ? '1分30秒'
          : editor.durationController.text.trim();
      final builtLesson = editor.buildLessonForPublication(
        title: title,
        durationLabel: durationLabel,
      );
      final previous = entry.$1 < _lastPersistedLessons.length
          ? _lastPersistedLessons[entry.$1]
          : null;
      lessons.add(
        previous == null
            ? builtLesson
            : builtLesson.copyWith(
                id: previous.id,
                order: previous.order,
                documentVersion: previous.documentVersion,
                quizVersion: previous.quizVersion,
                lessonEvents: previous.lessonEvents,
                createdAt: previous.createdAt,
                updatedAt: previous.updatedAt,
              ),
      );
    }

    return lessons;
  }

  Future<void> _saveLessons() async {
    if (_lessonEditors.any((editor) => editor.isAnySegmentUploading)) {
      setState(() {
        _message = 'アップロードが完了してから保存してください。';
      });
      return;
    }
    final lessons = _buildLessons();
    if (lessons == null) {
      return;
    }

    final courseId = widget.course.id;
    if (courseId == null && widget.onSaveOverride == null) {
      setState(() {
        _message = '講座IDがないため保存できません。';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final result = await _persistLessons(lessons, courseId: courseId);
      final savedLessons = result.lessons;
      final removedSegments = _collectRemovedMediaSegments(
        previousLessons: result.previousLessons,
        nextLessons: savedLessons,
      );

      _lastPersistedLessons = savedLessons;
      _loadedLessonContentVersion = result.lessonContentVersion;
      _loadedDraftRevisions.clear();
      _activeCourse = widget.lessonId == null
          ? _activeCourse.withLessonContent(savedLessons)
          : _replaceLessonInCourse(_activeCourse, savedLessons.single);

      if (mounted) {
        setState(() {
          for (var index = 0; index < _lessonEditors.length; index++) {
            if (index >= savedLessons.length) {
              continue;
            }
            final editor = _lessonEditors[index];
            editor.applySavedLesson(savedLessons[index]);
          }
          _message = 'レッスン情報を保存しました。';
        });
      }

      if (courseId != null && removedSegments.isNotEmpty) {
        unawaited(_deleteRemovedSegmentFiles(removedSegments));
      }
    } on LessonDocumentVersionConflict catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = describeFirebaseError(
            error,
            permissionDeniedMessage:
                '権限の情報が最新でない可能性があります。アプリを再起動するか、'
                '一度ログアウトして再度ログインしてから、もう一度お試しください。',
          );
        });
      }
    } on LessonPublicationValidationException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
    } on LessonPayloadValidationException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'エラーが発生しました: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Writes [lessons] to Firestore. If the write is rejected because the
  /// signed-in user's role/permission information looks out of date (for
  /// example, after switching roles or logging out from another device),
  /// this refreshes the auth token once and retries a single time before
  /// giving up.
  Future<_LessonSaveResult> _persistLessons(
    List<CourseLesson> lessons, {
    required String? courseId,
  }) async {
    try {
      return await _writeLessons(lessons, courseId: courseId);
    } on FirebaseException catch (error) {
      final isPermissionError =
          error.code == 'permission-denied' || error.code == 'unauthorized';
      if (!isPermissionError || !(await _tryRefreshAuthToken())) {
        rethrow;
      }
      return _writeLessons(lessons, courseId: courseId);
    }
  }

  Future<_LessonSaveResult> _writeLessons(
    List<CourseLesson> lessons, {
    required String? courseId,
  }) async {
    final saveOverride = widget.onSaveOverride;
    if (widget.lessonId != null && saveOverride == null) {
      final publishedLessons = _prepareLessonsForPublication(
        previousLessons: _lastPersistedLessons,
        nextLessons: lessons,
      );
      final saveResult = await _lessonRepository.saveLesson(
        courseId: courseId!,
        editedLesson: publishedLessons.single,
        expectedDocumentVersion: _loadedLessonContentVersion,
        expectedDraftRevision:
            _loadedDraftRevisions[_selectedLessonNumber] ?? 0,
      );
      return _LessonSaveResult(
        lessons: [saveResult.savedLesson],
        previousLessons: [saveResult.previousLesson],
        lessonContentVersion: saveResult.savedLesson.documentVersion,
      );
    }
    if (saveOverride != null) {
      final publishedLessons = _prepareLessonsForPublication(
        previousLessons: _lastPersistedLessons,
        nextLessons: lessons,
      );
      final nextVersion = nextLessonContentVersion(
        _loadedLessonContentVersion == 0 ? null : _loadedLessonContentVersion,
      );
      validateCourseDocumentForPersistence({
        ..._activeCourse.toFirestore(),
        'lessons': publishedLessons.map((lesson) => lesson.toMap()).toList(),
        'lessonCount': publishedLessons.length,
        'lessonContentVersion': nextVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await saveOverride(publishedLessons);
      return _LessonSaveResult(
        lessons: publishedLessons,
        previousLessons: _lastPersistedLessons,
        lessonContentVersion: nextVersion,
      );
    }
    final courseReference = FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId!);
    return FirebaseFirestore.instance.runTransaction<_LessonSaveResult>((
      transaction,
    ) async {
      final snapshot = await transaction.get(courseReference);
      if (!snapshot.exists) {
        throw StateError('講座が見つかりません。');
      }
      final snapshotData = snapshot.data() ?? const <String, dynamic>{};
      if (!lessonContentVersionMatches(
        snapshotData['lessonContentVersion'],
        _loadedLessonContentVersion,
      )) {
        throw const LessonPublicationValidationException(
          lessonContentVersionConflictMessage,
        );
      }
      final currentVersion = _loadedLessonContentVersion;
      final latestLessons = Course.fromFirestore(snapshot).lessons;
      if (latestLessons.length != lessons.length) {
        throw const LessonPublicationValidationException(
          lessonCountConflictMessage,
        );
      }
      final draftLessonCount = latestLessons.length > lessons.length
          ? latestLessons.length
          : lessons.length;
      final draftReferences = [
        for (var index = 0; index < draftLessonCount; index++)
          courseReference.collection('lessonDrafts').doc('${index + 1}'),
      ];
      final transactionDrafts = <int, BoardSet>{};
      final draftReferencesToDelete =
          <DocumentReference<Map<String, dynamic>>>[];
      for (var index = 0; index < draftReferences.length; index++) {
        final draftSnapshot = await transaction.get(draftReferences[index]);
        final draftData = draftSnapshot.data();
        final lessonNumber = index + 1;
        final expectedDraftRevision = _loadedDraftRevisions[lessonNumber] ?? 0;
        final matchingDraft = lessonDraftForPublication(
          draftData,
          lessonContentVersion: currentVersion,
          expectedDraftRevision: expectedDraftRevision,
        );
        if (matchingDraft != null) {
          draftReferencesToDelete.add(draftReferences[index]);
          transactionDrafts[lessonNumber] = matchingDraft.boardSet;
        }
      }
      final lessonsWithPersistedBoardSets = retainPersistedLessonBoardSets(
        latestLessons: latestLessons,
        editedLessons: lessons,
      );
      final nextLessonsWithDrafts = promoteLessonDraftBoardSets(
        lessonsWithPersistedBoardSets,
        transactionDrafts,
      );
      final publishedLessons = _prepareLessonsForPublication(
        previousLessons: latestLessons,
        nextLessons: nextLessonsWithDrafts,
      );
      final nextVersion = nextLessonContentVersion(
        snapshotData['lessonContentVersion'],
      );
      final lessonMaps = publishedLessons
          .map((lesson) => lesson.toMap())
          .toList();
      validateCourseDocumentForPersistence({
        ...snapshotData,
        'lessons': lessonMaps,
        'lessonCount': publishedLessons.length,
        'lessonContentVersion': nextVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(courseReference, {
        'lessons': lessonMaps,
        'lessonCount': publishedLessons.length,
        'lessonContentVersion': nextVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final draftReference in draftReferencesToDelete) {
        transaction.delete(draftReference);
      }
      return _LessonSaveResult(
        lessons: publishedLessons,
        previousLessons: latestLessons,
        lessonContentVersion: nextVersion,
      );
    });
  }

  Future<bool> _tryRefreshAuthToken() async {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Finds media parts that existed in the last known saved state but are
  /// missing from [nextLessons], so their uploaded files can be cleaned up
  /// from Storage once the save that removes them actually succeeds.
  List<String> _collectRemovedMediaSegments({
    required List<CourseLesson> previousLessons,
    required List<CourseLesson> nextLessons,
  }) {
    final removedUrls = <String>[];
    final lessonCount = previousLessons.length < nextLessons.length
        ? previousLessons.length
        : nextLessons.length;

    for (var index = 0; index < lessonCount; index++) {
      final nextSegmentIds = nextLessons[index].mediaSegments
          .map((segment) => segment.id)
          .toSet();
      final previousLesson = previousLessons[index];
      for (final segment in previousLesson.mediaSegments) {
        if (!previousLesson.lockedSegmentIds.contains(segment.id) &&
            segment.hasUrl &&
            !nextSegmentIds.contains(segment.id)) {
          removedUrls.add(segment.url);
        }
      }
    }
    return removedUrls;
  }

  /// Best-effort cleanup: deletes Storage files for media parts that were
  /// just removed by a successful "レッスン情報を保存". Failures are ignored
  /// so cleanup never affects the (already successful) save itself.
  Future<void> _deleteRemovedSegmentFiles(List<String> urls) async {
    for (final url in urls) {
      try {
        await widget.mediaStorageService.deleteFileAtUrl(url);
      } catch (_) {
        // 掃除に失敗しても保存自体は成功しているため、ここでは無視する。
      }
    }
  }

  Future<void> _uploadSegmentMedia({
    required int lessonNumber,
    required _LessonEditorState editor,
    required _MediaSegmentEditorState segment,
    bool showGuide = true,
  }) async {
    if (segment.isLocked) {
      setState(() {
        _message = lessonPublishedSegmentsLockedError;
      });
      return;
    }

    final courseId = widget.course.id;
    if (courseId == null) {
      setState(() {
        _message = '講座IDがないためアップロードできません。';
      });
      return;
    }

    if (showGuide && !kIsWeb) {
      final shouldPick = await _showUploadGuideDialog(
        mediaType: segment.mediaType,
      );
      if (!shouldPick || !mounted) {
        return;
      }
    }

    setState(() {
      _message = null;
    });

    PlatformFile? pickedFile;
    try {
      pickedFile = await widget.mediaStorageService.pickLessonMediaFile(
        mediaType: segment.mediaType,
      );
    } on LessonMediaStorageException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
      return;
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'ファイル選択に失敗しました: $error';
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    if (pickedFile == null) {
      setState(() {
        _message = 'ファイル選択をキャンセルしました。';
      });
      return;
    }

    final previousUrl = segment.urlController.text.trim();

    setState(() {
      segment.isUploading = true;
      segment.uploadProgress = 0;
      _message = null;
    });

    try {
      final result = await widget.mediaStorageService.uploadLessonMediaFile(
        courseId: courseId,
        lessonNumber: widget.lessonId == null ? lessonNumber : null,
        lessonId: widget.lessonId,
        segmentId: segment.id,
        mediaType: segment.mediaType,
        pickedFile: pickedFile,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            segment.uploadProgress = progress;
          });
        },
      );
      if (!mounted) {
        return;
      }

      final detectedDurationSec = await widget.durationService
          .detectDurationSec(pickedFile);

      segment.urlController.text = result.downloadUrl;
      if (detectedDurationSec != null && detectedDurationSec > 0) {
        segment.durationSec = detectedDurationSec;
      }
      setState(() {
        segment.isUploading = false;
        segment.uploadProgress = null;
        _message =
            'レッスン$lessonNumber のパート${segment.displayOrder}に'
            '${widget.mediaStorageService.mediaTypeLabel(segment.mediaType)}をアップロードしました。'
            '${detectedDurationSec != null ? '（再生時間: $detectedDurationSec秒）' : ''}'
            '「レッスン情報を保存」を押して反映してください。';
      });

      if (!segment.isLocked &&
          previousUrl.isNotEmpty &&
          previousUrl != result.downloadUrl) {
        // 同じパートにファイルを再アップロードした場合、古いファイルは
        // もう使われないため、Storage の容量を無駄にしないよう削除する。
        unawaited(
          widget.mediaStorageService
              .deleteFileAtUrl(previousUrl)
              .catchError((_) {}),
        );
      }
    } on LessonMediaStorageException catch (error) {
      if (mounted) {
        setState(() {
          segment.isUploading = false;
          segment.uploadProgress = null;
          _message = error.message;
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          segment.isUploading = false;
          segment.uploadProgress = null;
          _message =
              'アップロードに失敗しました: ${describeFirebaseError(error, permissionDeniedMessage: 'Storage へのアップロード権限がありません。Firebase のルール反映後に再試行してください。')}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          segment.isUploading = false;
          segment.uploadProgress = null;
          _message = 'アップロードに失敗しました: $error';
        });
      }
    }
  }

  Future<bool> _showUploadGuideDialog({required String mediaType}) async {
    final mediaLabel = widget.mediaStorageService.mediaTypeLabel(mediaType);
    final allowedExtensions = widget.mediaStorageService
        .allowedExtensionsForMediaType(mediaType);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('$mediaLabelファイルを選びます'),
          content: SingleChildScrollView(
            child: Text(
              '端末内の$mediaLabelファイルを選んでアップロードします。\n\n'
              '【エミュレータの場合】\n'
              '最初は「まだ一つも項目がありません」と出ることがあります。\n'
              'その場合は、先に PC から音声ファイルを Download フォルダへ入れてください。\n\n'
              '1. 画面の ≡（メニュー）または「ダウンロード」を開く\n'
              '2. test.mp3 などを選ぶ\n'
              '3. 戻るときは端末画面下の ◁（戻る）ボタン\n\n'
              '【対応形式】\n'
              '${allowedExtensions.join(' / ')}（50MBまで）',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ファイルを選ぶ'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _saveWhiteboardDraft({
    required int lessonIndex,
    required _LessonEditorState editor,
    required BoardSet boardSet,
  }) async {
    final courseId = widget.course.id;
    if (courseId == null) {
      throw StateError('講座IDがないため一時保存できません。');
    }

    final durationLabel = editor.durationController.text.trim().isEmpty
        ? '1分30秒'
        : editor.durationController.text.trim();

    final lessonNumber = widget.lessonId == null
        ? lessonIndex + 1
        : _selectedLessonNumber;
    final expectedDraftRevision = _loadedDraftRevisions[lessonNumber] ?? 0;
    final expectedNextDraftRevision = nextLessonDraftRevision(
      expectedDraftRevision == 0 ? null : expectedDraftRevision,
    );
    final versionedSaveOverride = widget.onVersionedLessonDraftSaveOverride;
    final saveOverride = widget.onLessonDraftSaveOverride;
    final int savedDraftRevision;
    if (versionedSaveOverride != null) {
      savedDraftRevision = await versionedSaveOverride(
        lessonNumber: lessonNumber,
        boardSet: boardSet,
        expectedLessonContentVersion: _loadedLessonContentVersion,
        expectedDraftRevision: expectedDraftRevision,
      );
    } else if (saveOverride != null) {
      await saveOverride(
        lessonNumber: lessonNumber,
        boardSet: boardSet,
        expectedLessonContentVersion: _loadedLessonContentVersion,
      );
      savedDraftRevision = expectedNextDraftRevision;
    } else if (widget.lessonId != null) {
      savedDraftRevision = await _lessonRepository.saveLessonDraft(
        courseId: courseId,
        lessonId: widget.lessonId!,
        expectedDocumentVersion: _loadedLessonContentVersion,
        expectedDraftRevision: expectedDraftRevision,
        boardSet: boardSet,
      );
    } else {
      savedDraftRevision = await saveLessonWhiteboardDraft(
        courseId: courseId,
        lessonIndex: lessonIndex,
        expectedLessonContentVersion: _loadedLessonContentVersion,
        expectedDraftRevision: expectedDraftRevision,
        currentLesson: editor.buildCurrentLesson(
          title: editor.titleController.text.trim(),
          durationLabel: durationLabel,
        ),
        boardSet: boardSet,
      );
    }
    if (savedDraftRevision != expectedNextDraftRevision) {
      throw StateError('書き物の下書きリビジョンが不正なため保存できません。');
    }
    _loadedDraftRevisions[lessonNumber] = savedDraftRevision;

    if (mounted) {
      setState(() {
        final draftLayers =
            boardSet.defaultBoard?.layerBundle.layers ??
            const <LessonWhiteboardLayer>[];
        editor.draftWhiteboardLayers = draftLayers;
        editor.draftBoardSet = boardSet;
        editor.workingBoardSet = boardSet;
        editor.workingWhiteboardLayers = LessonWhiteboardLayerBundle(
          layers: draftLayers,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseId = widget.course.id;
    final canUploadMedia = courseId != null && courseId.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('レッスン管理')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.course.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1レッスンに複数の音声・動画パートを追加できます。'
              'アップロード後は「レッスン情報を保存」を押してください。',
            ),
            if (!canUploadMedia) ...[
              const SizedBox(height: 8),
              Text(
                '講座IDがないため、この画面ではアップロードできません。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (_isLoadingLessons) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            if (!_isLoadingLessons)
              for (final entry in _lessonEditors.indexed) ...[
                _LessonEditorCardHost(
                  key: ObjectKey(entry.$2),
                  index: _lessonNumberForEditor(entry.$1),
                  lessonIndex: _lessonNumberForEditor(entry.$1) - 1,
                  course: _activeCourse,
                  editor: entry.$2,
                  canUploadMedia: canUploadMedia,
                  mediaConfig: _mediaConfig,
                  mediaStorageService: widget.mediaStorageService,
                  requiredText: _requiredText,
                  onAddSegment: (segment) {
                    unawaited(
                      _uploadSegmentMedia(
                        lessonNumber: _lessonNumberForEditor(entry.$1),
                        editor: entry.$2,
                        segment: segment,
                        showGuide: false,
                      ),
                    );
                  },
                  onUploadSegment: (segment) => _uploadSegmentMedia(
                    lessonNumber: _lessonNumberForEditor(entry.$1),
                    editor: entry.$2,
                    segment: segment,
                  ),
                  onDraftSaved: (boardSet) => _saveWhiteboardDraft(
                    lessonIndex: _lessonNumberForEditor(entry.$1) - 1,
                    editor: entry.$2,
                    boardSet: boardSet,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            if (_message != null) ...[
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isSaving) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed:
                  _isSaving ||
                      _isLoadingLessons ||
                      _lessonEditors.any(
                        (editor) => editor.isAnySegmentUploading,
                      )
                  ? null
                  : _saveLessons,
              icon: const Icon(Icons.save),
              label: const Text('レッスン情報を保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaSegmentEditorState {
  _MediaSegmentEditorState({
    required this.id,
    required this.order,
    required this.titleController,
    required this.urlController,
    required this.mediaType,
    this.isLocked = false,
    this.durationSec = 0,
  }) : isUploading = false,
       uploadProgress = null;

  factory _MediaSegmentEditorState.fromSegment(
    LessonMediaSegment segment, {
    required bool isLocked,
  }) {
    return _MediaSegmentEditorState(
      id: segment.id,
      order: segment.order,
      titleController: TextEditingController(text: segment.title),
      urlController: TextEditingController(text: segment.url),
      mediaType: segment.isAudio ? 'audio' : 'video',
      isLocked: isLocked,
      durationSec: segment.durationSec,
    );
  }

  final String id;
  int order;
  final TextEditingController titleController;
  final TextEditingController urlController;
  String mediaType;
  bool isLocked;
  int durationSec;
  bool isUploading;
  double? uploadProgress;

  int get displayOrder => order + 1;

  bool get hasUrl => urlController.text.trim().isNotEmpty;

  LessonMediaSegment toSegment({required int fallbackDurationSec}) {
    final duration = isLocked
        ? durationSec
        : (durationSec > 0 ? durationSec : fallbackDurationSec);
    return LessonMediaSegment(
      id: id,
      order: order,
      title: titleController.text.trim(),
      mediaType: mediaType == 'audio' ? 'audio' : 'video',
      url: urlController.text.trim(),
      durationSec: hasUrl ? duration : 0,
    );
  }

  void dispose() {
    titleController.dispose();
    urlController.dispose();
  }
}

class _LessonEditorState {
  _LessonEditorState({
    required this.titleController,
    required this.durationController,
    required this.segments,
    required this.isPreview,
    required this.playbackMode,
    required this.publishedSegmentIds,
    required this.publishedSegmentIdsMetadataValid,
    required this.contentRevision,
    required this.publishedBoardSet,
    required this.draftBoardSet,
    this.publishedWhiteboardLayers = const [],
    this.draftWhiteboardLayers = const [],
    LessonWhiteboardLayerBundle? workingWhiteboardLayers,
    BoardSet? workingBoardSet,
  }) : workingWhiteboardLayers =
           workingWhiteboardLayers ??
           mergeWhiteboardDraftLayers(
             published: LessonWhiteboardLayerBundle(
               layers: publishedWhiteboardLayers,
             ),
             draft: LessonWhiteboardLayerBundle(layers: draftWhiteboardLayers),
           ),
       workingBoardSet =
           workingBoardSet ??
           (draftBoardSet.isNotEmpty
               ? draftBoardSet
               : publishedBoardSet.isNotEmpty
               ? publishedBoardSet
               : const BoardSet());

  factory _LessonEditorState.fromLesson(CourseLesson lesson) {
    final segments = lesson.mediaSegments.isEmpty
        ? <_MediaSegmentEditorState>[]
        : lesson.mediaSegments
              .map(
                (segment) => _MediaSegmentEditorState.fromSegment(
                  segment,
                  isLocked: lesson.lockedSegmentIds.contains(segment.id),
                ),
              )
              .toList();

    return _LessonEditorState(
      titleController: TextEditingController(text: lesson.title),
      durationController: TextEditingController(text: lesson.duration),
      segments: segments,
      isPreview: lesson.isPreview,
      playbackMode: lesson.playbackMode,
      publishedSegmentIds: lesson.publishedSegmentIds,
      publishedSegmentIdsMetadataValid:
          lesson.hasValidPublishedSegmentIdsMetadata,
      contentRevision: lesson.contentRevision,
      publishedBoardSet: lesson.publishedBoardSet,
      draftBoardSet: lesson.draftBoardSet,
      publishedWhiteboardLayers: lesson.whiteboardLayers,
      draftWhiteboardLayers: lesson.whiteboardDraftLayers,
      workingWhiteboardLayers: mergeWhiteboardDraftLayers(
        published: lesson.publishedWhiteboardBundle,
        draft: lesson.draftWhiteboardBundle,
      ),
      workingBoardSet: lesson.draftBoardSet.isNotEmpty
          ? lesson.draftBoardSet
          : lesson.publishedBoardSet,
    );
  }

  final TextEditingController titleController;
  final TextEditingController durationController;
  final List<_MediaSegmentEditorState> segments;
  bool isPreview;
  LessonPlaybackMode playbackMode;
  List<String> publishedSegmentIds;
  bool publishedSegmentIdsMetadataValid;
  int contentRevision;
  BoardSet publishedBoardSet;
  BoardSet draftBoardSet;
  List<LessonWhiteboardLayer> publishedWhiteboardLayers;
  List<LessonWhiteboardLayer> draftWhiteboardLayers;
  LessonWhiteboardLayerBundle workingWhiteboardLayers;
  BoardSet workingBoardSet;

  bool get isAnySegmentUploading =>
      segments.any((segment) => segment.isUploading);

  bool get hasLockedSegments =>
      !publishedSegmentIdsMetadataValid || publishedSegmentIds.isNotEmpty;

  bool get hasPlayableMedia => segments.any((segment) => segment.hasUrl);

  bool get hasAudioSegment =>
      segments.any((segment) => segment.mediaType == 'audio' && segment.hasUrl);

  List<LessonMediaSegment> buildSegments({
    required String fallbackDurationLabel,
  }) {
    final fallbackDurationSec =
        parseLessonDurationLabel(fallbackDurationLabel) ?? 0;
    return LessonMediaSegment.normalizeOrders(
      segments
          .where((segment) => segment.isLocked || segment.hasUrl)
          .map(
            (segment) =>
                segment.toSegment(fallbackDurationSec: fallbackDurationSec),
          )
          .toList(),
    );
  }

  CourseLesson buildCurrentLesson({
    required String title,
    required String durationLabel,
  }) {
    return CourseLesson(
      title: title,
      duration: durationLabel,
      mediaSegments: buildSegments(fallbackDurationLabel: durationLabel),
      isPreview: isPreview,
      playbackMode: playbackMode,
      publishedSegmentIds: publishedSegmentIds,
      publishedSegmentIdsMetadataValid: publishedSegmentIdsMetadataValid,
      contentRevision: contentRevision,
      publishedBoardSet: publishedBoardSet,
      draftBoardSet: draftBoardSet,
    );
  }

  CourseLesson buildLessonForPublication({
    required String title,
    required String durationLabel,
  }) {
    final nextPublishedBoardSet = draftBoardSet.isNotEmpty
        ? draftBoardSet
        : publishedBoardSet.isNotEmpty
        ? publishedBoardSet
        : workingBoardSet.isNotEmpty
        ? workingBoardSet
        : workingWhiteboardLayers.isEmpty
        ? const BoardSet()
        : publishedBoardSet.copyWithDefaultLayerBundle(workingWhiteboardLayers);
    return CourseLesson(
      title: title,
      duration: durationLabel,
      mediaSegments: buildSegments(fallbackDurationLabel: durationLabel),
      isPreview: isPreview,
      playbackMode: playbackMode,
      publishedSegmentIds: publishedSegmentIds,
      publishedSegmentIdsMetadataValid: publishedSegmentIdsMetadataValid,
      contentRevision: contentRevision,
      publishedBoardSet: nextPublishedBoardSet,
      draftBoardSet: const BoardSet(),
    );
  }

  void applySavedLesson(CourseLesson lesson) {
    playbackMode = lesson.playbackMode;
    publishedSegmentIds = lesson.publishedSegmentIds;
    publishedSegmentIdsMetadataValid =
        lesson.hasValidPublishedSegmentIdsMetadata;
    contentRevision = lesson.contentRevision;
    publishedBoardSet = lesson.publishedBoardSet;
    draftBoardSet = lesson.draftBoardSet;
    publishedWhiteboardLayers = lesson.whiteboardLayers;
    draftWhiteboardLayers = lesson.whiteboardDraftLayers;
    workingWhiteboardLayers = lesson.publishedWhiteboardBundle;
    workingBoardSet = lesson.publishedBoardSet;
    final lockedIds = lesson.lockedSegmentIds;
    for (final segment in segments) {
      segment.isLocked = lockedIds.contains(segment.id);
    }
  }

  _MediaSegmentEditorState addSegment({String mediaType = 'audio'}) {
    final segment = _MediaSegmentEditorState(
      id: LessonMediaSegment.generateId(),
      order: segments.length,
      titleController: TextEditingController(),
      urlController: TextEditingController(),
      mediaType: mediaType,
    );
    segments.add(segment);
    return segment;
  }

  void moveSegmentUp(int index) {
    if (index <= 0 ||
        index >= segments.length ||
        segments[index].isLocked ||
        segments[index - 1].isLocked) {
      return;
    }
    final item = segments.removeAt(index);
    segments.insert(index - 1, item);
    _reindexSegments();
  }

  void moveSegmentDown(int index) {
    if (index < 0 ||
        index >= segments.length - 1 ||
        segments[index].isLocked ||
        segments[index + 1].isLocked) {
      return;
    }
    final item = segments.removeAt(index);
    segments.insert(index + 1, item);
    _reindexSegments();
  }

  void removeSegmentAt(int index) {
    if (index < 0 || index >= segments.length || segments[index].isLocked) {
      return;
    }
    segments.removeAt(index).dispose();
    _reindexSegments();
  }

  void _reindexSegments() {
    for (var index = 0; index < segments.length; index++) {
      segments[index].order = index;
    }
  }

  void dispose() {
    titleController.dispose();
    durationController.dispose();
    for (final segment in segments) {
      segment.dispose();
    }
  }
}

/// Owns a rebuild scope for a single lesson's editor card.
///
/// Without this, every keystroke or toggle inside any lesson card called
/// [State.setState] on the whole [TeacherLessonManagePage], which rebuilt
/// every other lesson card too - including any live audio/video preview
/// player they might have open. Keeping [onChanged] local to this widget
/// means editing lesson 1 no longer touches lesson 2 or 3's cards.
class _LessonEditorCardHost extends StatefulWidget {
  const _LessonEditorCardHost({
    super.key,
    required this.index,
    required this.lessonIndex,
    required this.course,
    required this.editor,
    required this.canUploadMedia,
    required this.mediaConfig,
    required this.mediaStorageService,
    required this.requiredText,
    required this.onAddSegment,
    required this.onUploadSegment,
    required this.onDraftSaved,
  });

  final int index;
  final int lessonIndex;
  final Course course;
  final _LessonEditorState editor;
  final bool canUploadMedia;
  final LessonMediaConfig mediaConfig;
  final LessonMediaStorageService mediaStorageService;
  final String? Function(String? value) requiredText;
  final ValueChanged<_MediaSegmentEditorState> onAddSegment;
  final ValueChanged<_MediaSegmentEditorState> onUploadSegment;
  final WhiteboardBoardSetDraftSaveCallback onDraftSaved;

  @override
  State<_LessonEditorCardHost> createState() => _LessonEditorCardHostState();
}

class _LessonEditorCardHostState extends State<_LessonEditorCardHost> {
  @override
  Widget build(BuildContext context) {
    return _LessonEditorCard(
      index: widget.index,
      lessonIndex: widget.lessonIndex,
      course: widget.course,
      editor: widget.editor,
      canUploadMedia: widget.canUploadMedia,
      mediaConfig: widget.mediaConfig,
      mediaStorageService: widget.mediaStorageService,
      requiredText: widget.requiredText,
      onChanged: () => setState(() {}),
      onAddSegment: widget.onAddSegment,
      onUploadSegment: widget.onUploadSegment,
      onDraftSaved: widget.onDraftSaved,
    );
  }
}

class _LessonEditorCard extends StatelessWidget {
  const _LessonEditorCard({
    required this.index,
    required this.lessonIndex,
    required this.course,
    required this.editor,
    required this.canUploadMedia,
    required this.mediaConfig,
    required this.mediaStorageService,
    required this.requiredText,
    required this.onChanged,
    required this.onAddSegment,
    required this.onUploadSegment,
    required this.onDraftSaved,
  });

  final int index;
  final int lessonIndex;
  final Course course;
  final _LessonEditorState editor;
  final bool canUploadMedia;
  final LessonMediaConfig mediaConfig;
  final LessonMediaStorageService mediaStorageService;
  final String? Function(String? value) requiredText;
  final VoidCallback onChanged;
  final ValueChanged<_MediaSegmentEditorState> onAddSegment;
  final ValueChanged<_MediaSegmentEditorState> onUploadSegment;
  final WhiteboardBoardSetDraftSaveCallback onDraftSaved;

  void _showAddSegmentDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          void addSegment(String mediaType) {
            final segment = editor.addSegment(mediaType: mediaType);
            onChanged();
            onAddSegment(segment);
            Navigator.of(dialogContext).pop();
          }

          return AlertDialog(
            title: const Text('パートを追加'),
            content: const Text('追加するファイルの種類を選んでください。'),
            actions: [
              TextButton(
                onPressed: () => addSegment('audio'),
                child: const Text('音声'),
              ),
              TextButton(
                onPressed: () => addSegment('video'),
                child: const Text('動画'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courseId = course.id ?? '';
    final durationLabel = editor.durationController.text.trim().isEmpty
        ? '1分30秒'
        : editor.durationController.text.trim();
    final builtSegments = editor.buildSegments(
      fallbackDurationLabel: durationLabel,
    );
    final canAddSegment = mediaConfig.canAddSegment(
      currentSegmentCount: editor.segments.length,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'レッスン$index',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.titleController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'レッスンタイトル',
              ),
              validator: requiredText,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.durationController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '時間（目安）',
                hintText: '例: 1分30秒',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<LessonPlaybackMode>(
              key: ValueKey('lesson-$lessonIndex-playback-mode'),
              initialValue: editor.playbackMode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '再生モード',
              ),
              items: [
                for (final mode in LessonPlaybackMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.displayLabel)),
              ],
              onChanged: editor.hasLockedSegments
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      editor.playbackMode = value;
                      onChanged();
                    },
            ),
            const SizedBox(height: 4),
            Text(
              _playbackModeExplanation(editor.playbackMode),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (editor.hasLockedSegments)
              Text(
                lessonPlaybackModeLockedError,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            const SizedBox(height: 16),
            Text('メディアパート', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (editor.segments.isEmpty)
              const Text('パートはまだありません。必要なときだけ追加できます。'),
            for (final entry in editor.segments.indexed) ...[
              _SegmentEditorTile(
                segment: entry.$2,
                segmentIndex: entry.$1,
                segmentCount: editor.segments.length,
                canUploadMedia:
                    canUploadMedia &&
                    !editor.isAnySegmentUploading &&
                    !entry.$2.isLocked,
                mediaStorageService: mediaStorageService,
                onChanged: onChanged,
                onUpload: () => onUploadSegment(entry.$2),
                onMoveUp:
                    !entry.$2.isLocked &&
                        entry.$1 > 0 &&
                        !editor.segments[entry.$1 - 1].isLocked
                    ? () {
                        editor.moveSegmentUp(entry.$1);
                        onChanged();
                      }
                    : null,
                onMoveDown:
                    !entry.$2.isLocked &&
                        entry.$1 < editor.segments.length - 1 &&
                        !editor.segments[entry.$1 + 1].isLocked
                    ? () {
                        editor.moveSegmentDown(entry.$1);
                        onChanged();
                      }
                    : null,
                onRemove: entry.$2.isLocked
                    ? null
                    : () {
                        editor.removeSegmentAt(entry.$1);
                        onChanged();
                      },
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !canAddSegment || editor.isAnySegmentUploading
                      ? null
                      : () => _showAddSegmentDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('パートを追加'),
                ),
                if (builtSegments.isNotEmpty)
                  Text(
                    '合計 ${builtSegments.fold<int>(0, (total, segment) => total + segment.durationSec)} 秒',
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('無料プレビュー'),
              value: editor.isPreview,
              onChanged: editor.isAnySegmentUploading
                  ? null
                  : (value) {
                      editor.isPreview = value;
                      onChanged();
                    },
            ),
            OutlinedButton.icon(
              onPressed: editor.isAnySegmentUploading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeacherQuizManagePage(
                            course: course,
                            lessonNumber: index,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.quiz),
              label: const Text('クイズを管理'),
            ),
            if (editor.hasPlayableMedia && courseId.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              LessonWhiteboardEditorPanel(
                key: ValueKey(
                  '${courseId}_${index}_${builtSegments.map((s) => s.id).join('_')}',
                ),
                courseId: courseId,
                lessonNumber: index,
                mediaSegments: builtSegments,
                durationLabel: durationLabel,
                publishedBoardSet: editor.publishedBoardSet,
                draftBoardSet: editor.draftBoardSet,
                onBoardSetDraftSaved: onDraftSaved,
                onBoardSetChanged: (boardSet) {
                  editor.workingBoardSet = boardSet;
                  editor.workingWhiteboardLayers =
                      boardSet.defaultBoard?.layerBundle ??
                      const LessonWhiteboardLayerBundle();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentEditorTile extends StatelessWidget {
  const _SegmentEditorTile({
    required this.segment,
    required this.segmentIndex,
    required this.segmentCount,
    required this.canUploadMedia,
    required this.mediaStorageService,
    required this.onChanged,
    required this.onUpload,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final _MediaSegmentEditorState segment;
  final int segmentIndex;
  final int segmentCount;
  final bool canUploadMedia;
  final LessonMediaStorageService mediaStorageService;
  final VoidCallback onChanged;
  final VoidCallback onUpload;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final mediaLabel = mediaStorageService.mediaTypeLabel(segment.mediaType);
    final allowedExtensions = mediaStorageService.allowedExtensionsForMediaType(
      segment.mediaType,
    );

    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'パート${segment.displayOrder}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (segment.isLocked)
              Text(
                '公開済み（タイトルのみ変更できます）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: segment.titleController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'パートタイトル（任意）',
                hintText: 'あとから変更できます',
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: segment.mediaType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '種類',
              ),
              items: const [
                DropdownMenuItem(value: 'audio', child: Text('音声')),
                DropdownMenuItem(value: 'video', child: Text('動画')),
              ],
              onChanged: segment.isUploading || segment.isLocked
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      segment.mediaType = value;
                      onChanged();
                    },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !canUploadMedia || segment.isUploading
                  ? null
                  : onUpload,
              icon: Icon(
                segment.mediaType == 'audio'
                    ? Icons.upload_file
                    : Icons.video_file_outlined,
              ),
              label: Text('$mediaLabelをアップロード'),
            ),
            const SizedBox(height: 4),
            Text(
              '対応形式: ${allowedExtensions.join(' / ')}（50MBまで）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (segment.isUploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: segment.uploadProgress?.clamp(0, 1),
              ),
            ],
            if (segment.hasUrl) ...[
              const SizedBox(height: 8),
              Text(
                'URL: ${segment.urlController.text}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (segment.durationSec > 0) Text('長さ: ${segment.durationSec}秒'),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: '上へ',
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '下へ',
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: '削除',
                  onPressed: segment.isUploading ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
