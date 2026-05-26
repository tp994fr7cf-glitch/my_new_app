import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';

typedef QuizSaveOverride = Future<void> Function(List<LessonEvent> events);

class TeacherQuizManagePage extends StatefulWidget {
  const TeacherQuizManagePage({
    super.key,
    required this.course,
    required this.lessonNumber,
    this.onSaveOverride,
  });

  final Course course;
  final int lessonNumber;
  final QuizSaveOverride? onSaveOverride;

  @override
  State<TeacherQuizManagePage> createState() => _TeacherQuizManagePageState();
}

class _TeacherQuizManagePageState extends State<TeacherQuizManagePage> {
  final List<_QuizEditorState> _quizEditors = [];
  late List<LessonEvent> _baseLessonEvents;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
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
    final editor = _QuizEditorState.empty(_quizEditors.length + 1);
    _attachEditorListeners(editor);
    return editor;
  }

  _QuizEditorState _createEditorFromEvent(LessonEvent event) {
    final editor = _QuizEditorState.fromEvent(event);
    _attachEditorListeners(editor);
    return editor;
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
    if (courseId == null ||
        widget.onSaveOverride != null ||
        Firebase.apps.isEmpty) {
      _isLoading = false;
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .get();
      if (!mounted) {
        return;
      }

      if (snapshot.exists) {
        final latestCourse = Course.fromFirestore(snapshot);
        setState(() {
          _baseLessonEvents = latestCourse.lessonEvents;
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
    if (_quizEditors.isEmpty) {
      return false;
    }

    return _quizEditors.every((editor) {
      final timestamp = int.tryParse(editor.timestampController.text.trim());
      final question = editor.questionController.text.trim();
      final choices = editor.choiceControllers
          .map((controller) => controller.text.trim())
          .where((choice) => choice.isNotEmpty)
          .toList();

      return timestamp != null &&
          timestamp >= 0 &&
          question.isNotEmpty &&
          choices.length >= 2 &&
          editor.correctChoiceIndex < choices.length;
    });
  }

  List<LessonEvent>? _buildLessonEvents() {
    final newEvents = <LessonEvent>[];

    for (final editor in _quizEditors) {
      final question = editor.questionController.text.trim();
      final choices = editor.choiceControllers
          .map((controller) => controller.text.trim())
          .where((choice) => choice.isNotEmpty)
          .toList();

      if (question.isEmpty || choices.length < 2) {
        setState(() {
          _message = '問題文と選択肢を2つ以上入力してください。';
        });
        return null;
      }

      if (editor.correctChoiceIndex >= choices.length) {
        setState(() {
          _message = '正解の選択肢を確認してください。';
        });
        return null;
      }

      newEvents.add(
        LessonEvent(
          id: editor.eventId,
          lessonNumber: widget.lessonNumber,
          timestampSec:
              int.tryParse(editor.timestampController.text.trim()) ?? 0,
          type: 'quiz',
          quiz: LessonQuiz(
            question: question,
            choices: choices,
            correctChoiceIndex: editor.correctChoiceIndex,
            explanation: editor.explanationController.text.trim(),
          ),
        ),
      );
    }

    final otherEvents = _baseLessonEvents.where((event) {
      return event.lessonNumber != widget.lessonNumber || event.type != 'quiz';
    });

    return [...otherEvents, ...newEvents]..sort((a, b) {
      final lessonCompare = a.lessonNumber.compareTo(b.lessonNumber);
      if (lessonCompare != 0) {
        return lessonCompare;
      }
      return a.timestampSec.compareTo(b.timestampSec);
    });
  }

  Future<void> _saveQuizzes() async {
    final events = _buildLessonEvents();
    if (events == null) {
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
      final saveOverride = widget.onSaveOverride;
      if (saveOverride != null) {
        await saveOverride(events);
      } else {
        await FirebaseFirestore.instance
            .collection('courses')
            .doc(courseId)
            .update({
              'lessonEvents': events.map((event) => event.toMap()).toList(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) {
        setState(() {
          _baseLessonEvents = events;
          _message = 'クイズを保存しました。';
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
    final lessonTitle = widget.course.lessons.length >= widget.lessonNumber
        ? widget.course.lessons[widget.lessonNumber - 1].title
        : 'レッスン${widget.lessonNumber}';

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
            const Text('授業の何秒地点でクイズを表示するかを設定できます。'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _addQuiz,
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
    required this.timestampController,
    required this.questionController,
    required this.choiceControllers,
    required this.correctChoiceIndex,
    required this.explanationController,
  });

  factory _QuizEditorState.empty(int index) {
    return _QuizEditorState(
      eventId: 'quiz-${DateTime.now().millisecondsSinceEpoch}-$index',
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
    required this.onChanged,
  });

  final int index;
  final _QuizEditorState editor;
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
            TextFormField(
              controller: editor.timestampController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '表示タイミング（秒）',
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
