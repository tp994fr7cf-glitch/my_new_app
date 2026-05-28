import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';

class TeacherInteractionManagePage extends StatelessWidget {
  const TeacherInteractionManagePage({super.key, required this.course});

  final Course course;

  String get _courseId => course.id ?? course.title.replaceAll('/', '_');

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
        .doc('${_courseId}_$lessonNumber')
        .set({
          'courseId': _courseId,
          'lessonNumber': lessonNumber,
          'instructorId': course.instructorId,
          'lessonNotesPublicEnabled': notesEnabled,
          'lessonQuestionsPublicEnabled': questionsEnabled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _setPublicNoteModeration(
    LessonNote note,
    String moderationStatus,
  ) async {
    if (Firebase.apps.isEmpty || note.id == null) {
      return;
    }
    await FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .doc(note.id)
        .set({
          'moderationStatus': moderationStatus,
          'moderatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _setPublicQuestionModeration(
    LessonQuestion question,
    String moderationStatus,
  ) async {
    if (Firebase.apps.isEmpty || question.id == null) {
      return;
    }
    await FirebaseFirestore.instance
        .collection('publicLessonQuestions')
        .doc(question.id)
        .set({
          'moderationStatus': moderationStatus,
          'moderatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
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
                      Card(
                        child: ListTile(
                          title: Text(
                            note.title.isEmpty ? '無題のメモ' : note.title,
                          ),
                          subtitle: Text(
                            '${note.authorName} / レッスン${note.lessonNumber}: ${note.lessonTitle}'
                            '${note.isTeacherHidden ? ' / 非公開化済み' : ''}',
                          ),
                          trailing: TextButton(
                            onPressed: () => _setPublicNoteModeration(
                              note,
                              note.isTeacherHidden
                                  ? lessonNoteModerationVisible
                                  : lessonNoteModerationHiddenByTeacher,
                            ),
                            child: Text(note.isTeacherHidden ? '公開化' : '非公開化'),
                          ),
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
                      Card(
                        child: ListTile(
                          title: Text(
                            question.title.isEmpty ? '無題の質問' : question.title,
                          ),
                          subtitle: Text(
                            '${question.authorName} / レッスン${question.lessonNumber}: ${question.lessonTitle}'
                            '${question.isTeacherHidden ? ' / 非公開化済み' : ''}',
                          ),
                          trailing: TextButton(
                            onPressed: () => _setPublicQuestionModeration(
                              question,
                              question.isTeacherHidden
                                  ? lessonNoteModerationVisible
                                  : lessonNoteModerationHiddenByTeacher,
                            ),
                            child: Text(
                              question.isTeacherHidden ? '公開化' : '非公開化',
                            ),
                          ),
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
