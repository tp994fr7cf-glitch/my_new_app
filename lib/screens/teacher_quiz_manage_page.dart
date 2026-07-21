import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_quiz_placement.dart';
import '../models/lesson_timed_anchor.dart';
import '../services/course_lesson_repository.dart';

typedef QuizSaveOverride = Future<void> Function(List<LessonEvent> events);
typedef QuizCourseLoadOverride = Future<Course?> Function();

const _legacyGlobalAnchorValue = '__legacy_global_anchor__';

class TeacherQuizManagePage extends StatefulWidget {
  const TeacherQuizManagePage({
    super.key,
    required this.course,
    required this.lessonNumber,
    this.onSaveOverride,
    this.onLoadCourseOverride,
  });

  final Course course;
  final int lessonNumber;
  final QuizSaveOverride? onSaveOverride;
  final QuizCourseLoadOverride? onLoadCourseOverride;

  @override
  State<TeacherQuizManagePage> createState() => _TeacherQuizManagePageState();
}

class _TeacherQuizManagePageState extends State<TeacherQuizManagePage> {
  final _lessonRepository = const CourseLessonRepository();
  final List<_QuizEditorState> _quizEditors = [];
  late List<LessonEvent> _baseLessonEvents;
  late Course _latestCourse;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _latestCourse = widget.course;
    _baseLessonEvents = widget.course.lessonEvents;
    _setQuizEditors(_lessonQuizEvents(_baseLessonEvents));
    _loadLatestQuizzes();
  }

  List<LessonEvent> _lessonQuizEvents(List<LessonEvent> events) {
    return events
        .where((event) => event.lessonNumber == widget.lessonNumber)
        .where((event) => event.isQuiz)
        .toList();
  }

  void _setQuizEditors(List<LessonEvent> quizEvents) {
    for (final editor in _quizEditors) {
      editor.dispose();
    }
    _quizEditors
      ..clear()
      ..addAll(quizEvents.map(_createEditorFromEvent));
  }

  _QuizEditorState _createEmptyEditor() {
    final editor = _QuizEditorState.empty(
      _quizEditors.length + 1,
      defaultSegmentId: _currentLesson == null
          ? null
          : defaultQuizSegmentId(_currentLesson!),
    );
    _attachEditorListeners(editor);
    return editor;
  }

  _QuizEditorState _createEditorFromEvent(LessonEvent event) {
    final editor = _QuizEditorState.fromEvent(event);
    _attachEditorListeners(editor);
    return editor;
  }

  CourseLesson? get _currentLesson {
    final lessonIndex = widget.lessonNumber - 1;
    if (lessonIndex < 0 || lessonIndex >= _latestCourse.lessons.length) {
      return null;
    }
    return _latestCourse.lessons[lessonIndex];
  }

  Course _courseWithUpdatedLesson(Course course, CourseLesson lesson) {
    final lessons = [...course.lessons];
    final index = lessons.indexWhere((item) => item.id == lesson.id);
    if (index < 0) {
      return course;
    }
    lessons[index] = lesson;
    return course.withLessonContent(sortCourseLessons(lessons));
  }

  void _attachEditorListeners(_QuizEditorState editor) {
    editor.timestampController.addListener(_refreshSaveState);
    editor.questionController.addListener(_refreshSaveState);
    for (final controller in editor.choiceControllers) {
      controller.addListener(_refreshSaveState);
    }
    editor.explanationController.addListener(_refreshSaveState);
  }

  void _refreshSaveState() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLatestQuizzes() async {
    final courseId = widget.course.id;
    final loadOverride = widget.onLoadCourseOverride;
    if (loadOverride == null &&
        (courseId == null ||
            widget.onSaveOverride != null ||
            Firebase.apps.isEmpty)) {
      _isLoading = false;
      return;
    }

    try {
      final Course? latestCourse;
      if (loadOverride != null) {
        latestCourse = await loadOverride();
      } else {
        final lessonId = _currentLesson?.id;
        if (lessonId == null) {
          latestCourse = null;
        } else {
          final lesson = await _lessonRepository.fetchLesson(
            courseId: courseId!,
            lessonId: lessonId,
          );
          latestCourse = lesson == null
              ? null
              : _courseWithUpdatedLesson(_latestCourse, lesson);
        }
      }
      if (!mounted) {
        return;
      }

      final loadedCourse = latestCourse;
      if (loadedCourse != null) {
        setState(() {
          _latestCourse = loadedCourse;
          _baseLessonEvents =
              loadedCourse.lessons[widget.lessonNumber - 1].lessonEvents;
          _setQuizEditors(_lessonQuizEvents(_baseLessonEvents));
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = '保存済みクイズの読み込みに失敗しました。';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final editor in _quizEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  void _addQuiz() {
    setState(() {
      _quizEditors.add(_createEmptyEditor());
      _message = null;
    });
  }

  bool get _canSave {
    final lesson = _currentLesson;
    if (_quizEditors.isEmpty || lesson == null) {
      return false;
    }

    return _quizEditors.every(
      (editor) => _editorValidationMessage(editor, lesson) == null,
    );
  }

  String? _editorValidationMessage(
    _QuizEditorState editor,
    CourseLesson lesson,
  ) {
    final timestamp = int.tryParse(editor.timestampController.text.trim());
    final question = editor.questionController.text.trim();
    final choices = editor.choiceControllers
        .map((controller) => controller.text.trim())
        .where((choice) => choice.isNotEmpty)
        .toList();
    if (timestamp == null || timestamp < 0) {
      return '表示タイミングは0秒以上で入力してください。';
    }
    if (question.isEmpty || choices.length < 2) {
      return '問題文と選択肢を2つ以上入力してください。';
    }
    if (editor.correctChoiceIndex >= choices.length) {
      return '正解の選択肢を確認してください。';
    }

    if (editor.selectedSegmentId == _legacyGlobalAnchorValue) {
      final wasLegacy =
          editor.originalEvent?.anchorType == LessonTimedAnchorType.global;
      if (!wasLegacy && lesson.effectivePublishedMediaSegments.isNotEmpty) {
        return '公開済みのパートを選択してください。';
      }
      return null;
    }
    final segment = lesson.mediaTimeline.segmentById(editor.selectedSegmentId);
    if (segment == null) {
      return '公開済みのパートを選択してください。';
    }
    if (timestamp >= segment.durationSec) {
      return '表示タイミングは選択したパートの0秒以上、${segment.durationSec}秒未満で入力してください。';
    }
    return null;
  }

  List<LessonEvent> _buildReplacementQuizEvents(Course latestCourse) {
    final lessonIndex = widget.lessonNumber - 1;
    if (lessonIndex < 0 || lessonIndex >= latestCourse.lessons.length) {
      throw const QuizPlacementException('対象のレッスンが見つかりません。');
    }
    final lesson = latestCourse.lessons[lessonIndex];
    final newEvents = <LessonEvent>[];

    for (final editor in _quizEditors) {
      final validationMessage = _editorValidationMessage(editor, lesson);
      if (validationMessage != null) {
        throw QuizPlacementException(validationMessage);
      }
      final question = editor.questionController.text.trim();
      final choices = editor.choiceControllers
          .map((controller) => controller.text.trim())
          .where((choice) => choice.isNotEmpty)
          .toList();
      final isLegacyGlobal =
          editor.selectedSegmentId == _legacyGlobalAnchorValue;
      final draft = LessonEvent(
        id: editor.eventId,
        lessonNumber: widget.lessonNumber,
        timestampSec: int.parse(editor.timestampController.text.trim()),
        type: 'quiz',
        quiz: LessonQuiz(
          question: question,
          choices: choices,
          correctChoiceIndex: editor.correctChoiceIndex,
          explanation: editor.explanationController.text.trim(),
        ),
        anchorType: isLegacyGlobal
            ? LessonTimedAnchorType.global
            : LessonTimedAnchorType.segment,
        segmentId: isLegacyGlobal ? null : editor.selectedSegmentId,
        quizVersion: editor.originalEvent?.quizVersion ?? 1,
      );
      validateQuizPlacement(
        event: draft,
        lesson: lesson,
        allowLegacyGlobal:
            editor.originalEvent?.anchorType == LessonTimedAnchorType.global ||
            lesson.effectivePublishedMediaSegments.isEmpty,
      );
      newEvents.add(
        LessonEvent(
          id: draft.id,
          lessonNumber: draft.lessonNumber,
          timestampSec: draft.timestampSec,
          type: draft.type,
          quiz: draft.quiz,
          anchorType: draft.anchorType,
          segmentId: draft.segmentId,
          quizVersion: draft.quizVersion,
        ).withResolvedGlobalTimestamp(lesson.mediaTimeline),
      );
    }
    return newEvents;
  }

  Future<void> _saveQuizzes() async {
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
      final saveOverride = widget.onSaveOverride;
      late List<LessonEvent> events;
      Course latestCourse = _latestCourse;
      if (saveOverride != null) {
        final replacementEvents = _buildReplacementQuizEvents(latestCourse);
        events = mergeLessonQuizEvents(
          latestEvents: _baseLessonEvents,
          baseEvents: _baseLessonEvents,
          lessonNumber: widget.lessonNumber,
          replacementQuizEvents: replacementEvents,
          lesson: latestCourse.lessons[widget.lessonNumber - 1],
        );
        validateCourseDocumentForPersistence({
          ...latestCourse.toFirestore(),
          'lessonEvents': events.map((event) => event.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await saveOverride(events);
      } else {
        final lesson = _currentLesson;
        final lessonId = lesson?.id;
        if (lesson == null || lessonId == null) {
          throw const QuizPlacementException('対象のレッスンが見つかりません。');
        }
        final replacementEvents = _buildReplacementQuizEvents(latestCourse);
        events = mergeLessonQuizEvents(
          latestEvents: lesson.lessonEvents,
          baseEvents: _baseLessonEvents,
          lessonNumber: widget.lessonNumber,
          replacementQuizEvents: replacementEvents,
          lesson: lesson,
        );
        final savedLesson = await _lessonRepository.saveLessonEvents(
          courseId: courseId!,
          lessonId: lessonId,
          expectedDocumentVersion: lesson.documentVersion,
          lessonEvents: events,
        );
        latestCourse = _courseWithUpdatedLesson(latestCourse, savedLesson);
      }

      if (mounted) {
        setState(() {
          _latestCourse = latestCourse;
          _baseLessonEvents = events;
          _setQuizEditors(_lessonQuizEvents(events));
          _message = 'クイズを保存しました。';
        });
      }
    } on LessonDocumentVersionConflict catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
    } on QuizPlacementException catch (error) {
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
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message ?? 'クイズの保存に失敗しました。';
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

  @override
  Widget build(BuildContext context) {
    final lesson = _currentLesson;
    final lessonTitle = lesson != null
        ? lesson.title
        : 'レッスン${widget.lessonNumber}';
    final publishedSegments =
        lesson?.effectivePublishedMediaSegments ?? const <LessonMediaSegment>[];
    final independentWithoutParts =
        lesson?.playbackMode.isIndependent == true && publishedSegments.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('クイズ管理')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              lessonTitle,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('公開済みパートと、そのパート内でクイズを表示する秒数を設定できます。'),
            if (independentWithoutParts) ...[
              const SizedBox(height: 8),
              Text(
                '独立再生では、クイズを追加する前にメディアパートを公開してください。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isLoading || independentWithoutParts
                  ? null
                  : _addQuiz,
              icon: const Icon(Icons.add),
              label: const Text('クイズを追加'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isLoading || _isSaving || !_canSave
                  ? null
                  : _saveQuizzes,
              icon: const Icon(Icons.save),
              label: const Text('クイズを保存'),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_quizEditors.isEmpty) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('まだクイズがありません。「クイズを追加」から作成してください。'),
                ),
              ),
              const SizedBox(height: 16),
            ] else
              for (final entry in _quizEditors.indexed) ...[
                _QuizEditorCard(
                  index: entry.$1 + 1,
                  editor: entry.$2,
                  publishedSegments: publishedSegments,
                  allowLegacyGlobal:
                      entry.$2.originalEvent?.anchorType ==
                          LessonTimedAnchorType.global ||
                      (publishedSegments.isEmpty &&
                          lesson?.playbackMode.isIndependent != true),
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 16),
              ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
            ],
            if (_isSaving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuizEditorState {
  _QuizEditorState({
    required this.eventId,
    required this.originalEvent,
    required this.selectedSegmentId,
    required this.timestampController,
    required this.questionController,
    required this.choiceControllers,
    required this.correctChoiceIndex,
    required this.explanationController,
  });

  factory _QuizEditorState.empty(
    int index, {
    required String? defaultSegmentId,
  }) {
    return _QuizEditorState(
      eventId: 'quiz-${DateTime.now().millisecondsSinceEpoch}-$index',
      originalEvent: null,
      selectedSegmentId: defaultSegmentId ?? _legacyGlobalAnchorValue,
      timestampController: TextEditingController(text: '0'),
      questionController: TextEditingController(),
      choiceControllers: [
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
      ],
      correctChoiceIndex: 0,
      explanationController: TextEditingController(),
    );
  }

  factory _QuizEditorState.fromEvent(LessonEvent event) {
    final quiz = event.quiz!;
    final choices = [
      ...quiz.choices,
      for (var i = quiz.choices.length; i < 4; i++) '',
    ];

    return _QuizEditorState(
      eventId: event.id,
      originalEvent: event,
      selectedSegmentId: event.anchorType == LessonTimedAnchorType.global
          ? _legacyGlobalAnchorValue
          : (event.segmentId ?? ''),
      timestampController: TextEditingController(text: '${event.timestampSec}'),
      questionController: TextEditingController(text: quiz.question),
      choiceControllers: choices
          .take(4)
          .map((choice) => TextEditingController(text: choice))
          .toList(),
      correctChoiceIndex: quiz.correctChoiceIndex,
      explanationController: TextEditingController(text: quiz.explanation),
    );
  }

  final String eventId;
  final LessonEvent? originalEvent;
  String selectedSegmentId;
  final TextEditingController timestampController;
  final TextEditingController questionController;
  final List<TextEditingController> choiceControllers;
  int correctChoiceIndex;
  final TextEditingController explanationController;

  void dispose() {
    timestampController.dispose();
    questionController.dispose();
    for (final controller in choiceControllers) {
      controller.dispose();
    }
    explanationController.dispose();
  }
}

class _QuizEditorCard extends StatelessWidget {
  const _QuizEditorCard({
    required this.index,
    required this.editor,
    required this.publishedSegments,
    required this.allowLegacyGlobal,
    required this.onChanged,
  });

  final int index;
  final _QuizEditorState editor;
  final List<LessonMediaSegment> publishedSegments;
  final bool allowLegacyGlobal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'クイズ$index',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  publishedSegments.any(
                        (segment) => segment.id == editor.selectedSegmentId,
                      ) ||
                      (allowLegacyGlobal &&
                          editor.selectedSegmentId == _legacyGlobalAnchorValue)
                  ? editor.selectedSegmentId
                  : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '表示するパート',
              ),
              items: [
                if (allowLegacyGlobal)
                  const DropdownMenuItem(
                    value: _legacyGlobalAnchorValue,
                    child: Text('レッスン全体（以前の形式）'),
                  ),
                for (final entry in publishedSegments.indexed)
                  DropdownMenuItem(
                    value: entry.$2.id,
                    child: Text(
                      'パート${entry.$1 + 1}'
                      '${entry.$2.title.trim().isEmpty ? '' : '：${entry.$2.title.trim()}'}',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                editor.selectedSegmentId = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.timestampController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '表示タイミング（秒）',
                helperText: '選択したパートの開始位置から数えた秒数です。',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.questionController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '問題文',
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in editor.choiceControllers.indexed) ...[
              TextFormField(
                controller: entry.$2,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: '選択肢${entry.$1 + 1}',
                ),
              ),
              const SizedBox(height: 8),
            ],
            DropdownButtonFormField<int>(
              initialValue: editor.correctChoiceIndex,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '正解',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('選択肢1')),
                DropdownMenuItem(value: 1, child: Text('選択肢2')),
                DropdownMenuItem(value: 2, child: Text('選択肢3')),
                DropdownMenuItem(value: 3, child: Text('選択肢4')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                editor.correctChoiceIndex = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.explanationController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '解説',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
