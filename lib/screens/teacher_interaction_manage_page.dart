import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';
import '../services/lesson_interaction_service.dart';

class TeacherInteractionManagePage extends StatelessWidget {
  const TeacherInteractionManagePage({super.key, required this.course});

  final Course course;
  static const _lessonInteractionService = LessonInteractionService();

  String get _courseId => course.storageId;

  Future<void> _setPlatformEnabled({
    required int lessonNumber,
    required bool notesEnabled,
    required bool questionsEnabled,
  }) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    await FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .doc(
          _lessonInteractionService.settingDocumentId(
            courseId: _courseId,
            lessonNumber: lessonNumber,
          ),
        )
        .set({
          'courseId': _courseId,
          'lessonNumber': lessonNumber,
          'instructorId': course.instructorId,
          'lessonNotesPublicEnabled': notesEnabled,
          'lessonQuestionsPublicEnabled': questionsEnabled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _setPublicModeration({
    required String collectionPath,
    required String? documentId,
    required String moderationStatus,
  }) async {
    await _lessonInteractionService.setPublicModeration(
      collectionPath: collectionPath,
      documentId: documentId,
      moderationStatus: moderationStatus,
    );
  }

  Stream<List<LessonNote>> _publicNotesStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .snapshots()
        .map((snapshot) {
          return sortLessonNotesByUpdatedAt(
            snapshot.docs
                .map(LessonNote.fromFirestore)
                .where((note) => !note.isDeleted)
                .toList(),
          );
        });
  }

  Stream<List<LessonQuestion>> _publicQuestionsStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('publicLessonQuestions')
        .where('courseId', isEqualTo: _courseId)
        .snapshots()
        .map((snapshot) {
          return sortLessonQuestionsByUpdatedAt(
            snapshot.docs
                .map(LessonQuestion.fromFirestore)
                .where((question) => !question.isDeleted)
                .toList(),
          );
        });
  }

  Stream<Map<int, _LessonInteractionSetting>> _settingsStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const {});
    }
    return FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .where('courseId', isEqualTo: _courseId)
        .snapshots()
        .map((snapshot) {
          return {
            for (final doc in snapshot.docs)
              (doc.data()['lessonNumber'] as num?)?.toInt() ?? 1:
                  _LessonInteractionSetting.fromMap(doc.data()),
          };
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公開メモ・質問管理')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              course.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('公開メモ欄・公開質問欄の公開状態と、公開投稿の個別非公開化を管理します。'),
            const SizedBox(height: 24),
            StreamBuilder<Map<int, _LessonInteractionSetting>>(
              stream: _settingsStream(),
              builder: (context, snapshot) {
                final settings = snapshot.data ?? const {};
                return Column(
                  children: [
                    for (final entry in course.lessons.indexed)
                      _LessonSettingCard(
                        lessonNumber: entry.$1 + 1,
                        lesson: entry.$2,
                        setting: settings[entry.$1 + 1],
                        onChanged: _setPlatformEnabled,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '公開メモ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<LessonNote>>(
              stream: _publicNotesStream(),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <LessonNote>[];
                if (notes.isEmpty) {
                  return const Text('公開メモはまだありません。');
                }
                return Column(
                  children: [
                    for (final note in notes)
                      _PublicNoteCard(
                        note: note,
                        onTap: () => _showNoteDetails(context, note),
                        onToggleModeration: () => _setPublicModeration(
                          collectionPath: 'publicLessonNotes',
                          documentId: note.id,
                          moderationStatus: note.isTeacherHidden
                              ? lessonNoteModerationVisible
                              : lessonNoteModerationHiddenByTeacher,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '公開質問',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<LessonQuestion>>(
              stream: _publicQuestionsStream(),
              builder: (context, snapshot) {
                final questions = snapshot.data ?? const <LessonQuestion>[];
                if (questions.isEmpty) {
                  return const Text('公開質問はまだありません。');
                }
                return Column(
                  children: [
                    for (final question in questions)
                      _PublicQuestionCard(
                        question: question,
                        onTap: () => _showQuestionDetails(context, question),
                        onToggleModeration: () => _setPublicModeration(
                          collectionPath: 'publicLessonQuestions',
                          documentId: question.id,
                          moderationStatus: question.isTeacherHidden
                              ? lessonNoteModerationVisible
                              : lessonNoteModerationHiddenByTeacher,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNoteDetails(BuildContext context, LessonNote note) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_noteTitle(note)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: '投稿者', value: _authorName(note.authorName)),
                _DetailRow(
                  label: 'レッスン',
                  value: 'レッスン${note.lessonNumber}: ${note.lessonTitle}',
                ),
                _DetailRow(label: '状態', value: _statusText(note)),
                const SizedBox(height: 16),
                _DetailSection(
                  title: '本文',
                  body: note.body.isEmpty ? '本文はありません。' : note.body,
                ),
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DetailSection(title: 'タグ', body: note.tags.join(' / ')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showQuestionDetails(
    BuildContext context,
    LessonQuestion question,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_questionHeadline(question)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(
                  label: '投稿者',
                  value: _authorName(question.authorName),
                ),
                _DetailRow(
                  label: 'レッスン',
                  value:
                      'レッスン${question.lessonNumber}: ${question.lessonTitle}',
                ),
                _DetailRow(label: '状態', value: _statusText(question)),
                const SizedBox(height: 16),
                _DetailSection(
                  title: '質問本文',
                  body: question.body.isEmpty ? '本文はありません。' : question.body,
                ),
                if ((question.quotedNoteTitle ?? '').isNotEmpty ||
                    (question.quotedNoteBody ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: '引用メモ',
                    body: [
                      if ((question.quotedNoteTitle ?? '').isNotEmpty)
                        question.quotedNoteTitle!,
                      if ((question.quotedNoteBody ?? '').isNotEmpty)
                        question.quotedNoteBody!,
                    ].join('\n'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }
}

class _PublicNoteCard extends StatelessWidget {
  const _PublicNoteCard({
    required this.note,
    required this.onTap,
    required this.onToggleModeration,
  });

  final LessonNote note;
  final VoidCallback onTap;
  final VoidCallback onToggleModeration;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(_noteTitle(note)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_previewText(note.body)),
            ],
            const SizedBox(height: 8),
            Text(
              '${_authorName(note.authorName)} / '
              'レッスン${note.lessonNumber}: ${note.lessonTitle}',
            ),
            const SizedBox(height: 8),
            _StatusWrap(labels: _statusLabels(note)),
          ],
        ),
        trailing: TextButton(
          onPressed: onToggleModeration,
          child: Text(note.isTeacherHidden ? '公開化' : '非公開化'),
        ),
      ),
    );
  }
}

class _PublicQuestionCard extends StatelessWidget {
  const _PublicQuestionCard({
    required this.question,
    required this.onTap,
    required this.onToggleModeration,
  });

  final LessonQuestion question;
  final VoidCallback onTap;
  final VoidCallback onToggleModeration;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(_questionHeadline(question)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              '${_authorName(question.authorName)} / '
              'レッスン${question.lessonNumber}: ${question.lessonTitle}',
            ),
            if ((question.quotedNoteTitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('引用メモ: ${question.quotedNoteTitle}'),
            ],
            const SizedBox(height: 8),
            _StatusWrap(labels: _statusLabels(question)),
          ],
        ),
        trailing: TextButton(
          onPressed: onToggleModeration,
          child: Text(question.isTeacherHidden ? '公開化' : '非公開化'),
        ),
      ),
    );
  }
}

class _StatusWrap extends StatelessWidget {
  const _StatusWrap({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final label in labels)
          Chip(
            label: Text(label),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SelectableText(body),
      ],
    );
  }
}

String _noteTitle(LessonNote note) {
  final title = note.title.trim();
  return title.isEmpty ? '無題のメモ' : title;
}

String _questionHeadline(LessonQuestion question) {
  return _previewText(question.body, fallback: '本文のない質問');
}

String _previewText(
  String text, {
  String fallback = '本文はありません。',
  int maxLength = 80,
}) {
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return fallback;
  }
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}...';
}

String _authorName(String authorName) {
  final trimmed = authorName.trim();
  return trimmed.isEmpty ? '投稿者不明' : trimmed;
}

List<String> _statusLabels(Object item) {
  final isTeacherHidden = item is LessonNote
      ? item.isTeacherHidden
      : item is LessonQuestion
      ? item.isTeacherHidden
      : false;
  final isStudentPublic = item is LessonNote
      ? item.isStudentPublic
      : item is LessonQuestion
      ? item.isStudentPublic
      : true;

  return [
    if (isTeacherHidden) '先生が非公開化済み',
    if (!isTeacherHidden && isStudentPublic) '学習者にも公開中',
    if (!isStudentPublic) '先生だけ表示',
  ];
}

String _statusText(Object item) {
  return _statusLabels(item).join(' / ');
}

class _LessonSettingCard extends StatelessWidget {
  const _LessonSettingCard({
    required this.lessonNumber,
    required this.lesson,
    required this.setting,
    required this.onChanged,
  });

  final int lessonNumber;
  final CourseLesson lesson;
  final _LessonInteractionSetting? setting;
  final Future<void> Function({
    required int lessonNumber,
    required bool notesEnabled,
    required bool questionsEnabled,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    final notesEnabled = setting?.notesEnabled ?? true;
    final questionsEnabled = setting?.questionsEnabled ?? true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'レッスン$lessonNumber: ${lesson.title}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('公開メモ欄を公開する'),
              value: notesEnabled,
              onChanged: (value) {
                onChanged(
                  lessonNumber: lessonNumber,
                  notesEnabled: value,
                  questionsEnabled: questionsEnabled,
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('公開質問欄を公開する'),
              value: questionsEnabled,
              onChanged: (value) {
                onChanged(
                  lessonNumber: lessonNumber,
                  notesEnabled: notesEnabled,
                  questionsEnabled: value,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonInteractionSetting {
  const _LessonInteractionSetting({
    required this.notesEnabled,
    required this.questionsEnabled,
  });

  final bool notesEnabled;
  final bool questionsEnabled;

  factory _LessonInteractionSetting.fromMap(Map<String, dynamic> data) {
    return _LessonInteractionSetting(
      notesEnabled: data['lessonNotesPublicEnabled'] != false,
      questionsEnabled: data['lessonQuestionsPublicEnabled'] != false,
    );
  }
}
