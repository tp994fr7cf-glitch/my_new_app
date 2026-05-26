import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';

typedef LessonSaveOverride = Future<void> Function(List<CourseLesson> lessons);

class TeacherLessonManagePage extends StatefulWidget {
  const TeacherLessonManagePage({
    super.key,
    required this.course,
    this.onSaveOverride,
  });

  final Course course;
  final LessonSaveOverride? onSaveOverride;

  @override
  State<TeacherLessonManagePage> createState() =>
      _TeacherLessonManagePageState();
}

class _TeacherLessonManagePageState extends State<TeacherLessonManagePage> {
  late final List<_LessonEditorState> _lessonEditors;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _lessonEditors = widget.course.lessons
        .map(_LessonEditorState.fromLesson)
        .toList();
  }

  @override
  void dispose() {
    for (final editor in _lessonEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '入力してください';
    }
    return null;
  }

  List<CourseLesson>? _buildLessons() {
    final lessons = <CourseLesson>[];

    for (final editor in _lessonEditors) {
      final title = editor.titleController.text.trim();
      if (title.isEmpty) {
        setState(() {
          _message = 'レッスンタイトルを入力してください。';
        });
        return null;
      }

      lessons.add(
        CourseLesson(
          title: title,
          duration: editor.durationController.text.trim().isEmpty
              ? '未設定'
              : editor.durationController.text.trim(),
          mediaType: editor.mediaType,
          mediaUrl: editor.mediaUrlController.text.trim(),
          isPreview: editor.isPreview,
        ),
      );
    }

    return lessons;
  }

  Future<void> _saveLessons() async {
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
      final saveOverride = widget.onSaveOverride;
      if (saveOverride != null) {
        await saveOverride(lessons);
      } else {
        await FirebaseFirestore.instance
            .collection('courses')
            .doc(courseId)
            .update({
              'lessons': lessons.map((lesson) => lesson.toMap()).toList(),
              'lessonCount': lessons.length,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) {
        setState(() {
          _message = 'レッスン情報を保存しました。';
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message ?? 'レッスン情報の保存に失敗しました。';
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
            const Text('動画・音声ファイル本体のアップロードは後で追加します。今は種別と仮URLを管理します。'),
            const SizedBox(height: 24),
            for (final entry in _lessonEditors.indexed) ...[
              _LessonEditorCard(
                index: entry.$1 + 1,
                editor: entry.$2,
                requiredText: _requiredText,
                onChanged: () => setState(() {}),
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
              onPressed: _isSaving ? null : _saveLessons,
              icon: const Icon(Icons.save),
              label: const Text('レッスン情報を保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonEditorState {
  _LessonEditorState({
    required this.titleController,
    required this.durationController,
    required this.mediaUrlController,
    required this.mediaType,
    required this.isPreview,
  });

  factory _LessonEditorState.fromLesson(CourseLesson lesson) {
    return _LessonEditorState(
      titleController: TextEditingController(text: lesson.title),
      durationController: TextEditingController(text: lesson.duration),
      mediaUrlController: TextEditingController(text: lesson.mediaUrl),
      mediaType: lesson.mediaType == 'audio' ? 'audio' : 'video',
      isPreview: lesson.isPreview,
    );
  }

  final TextEditingController titleController;
  final TextEditingController durationController;
  final TextEditingController mediaUrlController;
  String mediaType;
  bool isPreview;

  void dispose() {
    titleController.dispose();
    durationController.dispose();
    mediaUrlController.dispose();
  }
}

class _LessonEditorCard extends StatelessWidget {
  const _LessonEditorCard({
    required this.index,
    required this.editor,
    required this.requiredText,
    required this.onChanged,
  });

  final int index;
  final _LessonEditorState editor;
  final String? Function(String? value) requiredText;
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
                labelText: '時間',
                hintText: '例: 15分',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: editor.mediaType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '授業形式',
              ),
              items: const [
                DropdownMenuItem(value: 'video', child: Text('動画')),
                DropdownMenuItem(value: 'audio', child: Text('音声のみ')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                editor.mediaType = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.mediaUrlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '動画・音声URL（仮）',
                hintText: '後でFirebase StorageなどのURLを入れます',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('無料プレビュー'),
              value: editor.isPreview,
              onChanged: (value) {
                editor.isPreview = value;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}
