import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';
import 'lesson_notes_page.dart';
import 'lesson_questions_page.dart';

class LearningRecordsPage extends StatefulWidget {
  const LearningRecordsPage({
    super.key,
    required this.user,
    this.learningEventsStream,
    this.lessonViewSegmentsStream,
    this.quizAttemptsStream,
    this.lessonNotesStream,
    this.lessonQuestionsStream,
    this.lessonQuestionAnswersStream,
  });

  final User user;
  final Stream<List<Map<String, dynamic>>>? learningEventsStream;
  final Stream<List<Map<String, dynamic>>>? lessonViewSegmentsStream;
  final Stream<List<Map<String, dynamic>>>? quizAttemptsStream;
  final Stream<List<LessonNote>>? lessonNotesStream;
  final Stream<List<LessonQuestion>>? lessonQuestionsStream;
  final Stream<List<LessonQuestionAnswer>>? lessonQuestionAnswersStream;

  @override
  State<LearningRecordsPage> createState() => _LearningRecordsPageState();
}

enum _RecordType { views, quizzes, notes, comments }

enum _PeriodFilter { all, today, sevenDays, thirtyDays }

enum _CommentRecordType { questions, answers }

class _LearningRecordsPageState extends State<LearningRecordsPage> {
  _RecordType _selectedType = _RecordType.views;
  _PeriodFilter _selectedPeriod = _PeriodFilter.all;
  _CommentRecordType _selectedCommentType = _CommentRecordType.questions;
  String _query = '';

  Stream<List<Map<String, dynamic>>> _learningEventsStream() {
    final providedStream = widget.learningEventsStream;
    if (providedStream != null) {
      return providedStream;
    }

    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('learningEvents')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> _lessonViewSegmentsStream() {
    final providedStream = widget.lessonViewSegmentsStream;
    if (providedStream != null) {
      return providedStream;
    }

    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('lessonViewSegments')
        .orderBy('lastActivityAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> _quizAttemptsStream() {
    final providedStream = widget.quizAttemptsStream;
    if (providedStream != null) {
      return providedStream;
    }

    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('quizAttempts')
        .orderBy('answeredAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Stream<List<LessonNote>> _lessonNotesStream() {
    final providedStream = widget.lessonNotesStream;
    if (providedStream != null) {
      return providedStream;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('lessonNotes')
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(LessonNote.fromFirestore)
              .where((note) => !note.isDeleted)
              .toList();
        });
  }

  Stream<List<LessonQuestion>> _lessonQuestionsStream() {
    final providedStream = widget.lessonQuestionsStream;
    if (providedStream != null) {
      return providedStream;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('lessonQuestions')
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(LessonQuestion.fromFirestore)
              .where((question) => !question.isDeleted)
              .toList();
        });
  }

  Stream<List<LessonQuestionAnswer>> _lessonQuestionAnswersStream() {
    final providedStream = widget.lessonQuestionAnswersStream;
    if (providedStream != null) {
      return providedStream;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('lessonQuestionAnswers')
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(LessonQuestionAnswer.fromFirestore)
              .where((answer) => !answer.isDeleted)
              .toList();
        });
  }

  List<Map<String, dynamic>> _filterByPeriod(
    List<Map<String, dynamic>> records,
    String timestampField,
  ) {
    final since = _periodStart();
    if (since == null) {
      return records;
    }

    return records.where((record) {
      final timestamp = record[timestampField];
      if (timestamp is! Timestamp) {
        return false;
      }
      return !timestamp.toDate().isBefore(since);
    }).toList();
  }

  List<Map<String, dynamic>> _filterViewRecordsByPeriod(
    List<Map<String, dynamic>> records,
  ) {
    final since = _periodStart();
    if (since == null) {
      return records;
    }

    return records.where((record) {
      final timestamp =
          record['completedAt'] ?? record['startedAt'] ?? record['createdAt'];
      if (timestamp is! Timestamp) {
        return false;
      }
      return !timestamp.toDate().isBefore(since);
    }).toList();
  }

  DateTime? _periodStart() {
    final now = DateTime.now();
    return switch (_selectedPeriod) {
      _PeriodFilter.all => null,
      _PeriodFilter.today => DateTime(now.year, now.month, now.day),
      _PeriodFilter.sevenDays => now.subtract(const Duration(days: 7)),
      _PeriodFilter.thirtyDays => now.subtract(const Duration(days: 30)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学習記録')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '学習記録',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('視聴、クイズ回答、質問・回答コメントの記録を切り替えて確認できます。'),
            const SizedBox(height: 24),
            _RecordTypeSelector(
              selectedType: _selectedType,
              onSelected: (type) {
                setState(() {
                  _selectedType = type;
                  if (type == _RecordType.comments) {
                    _selectedCommentType = _CommentRecordType.questions;
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _PeriodFilterChips(
              selectedPeriod: _selectedPeriod,
              onSelected: (period) {
                setState(() {
                  _selectedPeriod = period;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '講座名・レッスン名・本文などで検索',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
            const SizedBox(height: 24),
            switch (_selectedType) {
              _RecordType.views => _ViewRecordsList(
                segmentRecordsStream: _lessonViewSegmentsStream(),
                legacyRecordsStream: _learningEventsStream(),
                filterRecords: _filterViewRecordsByPeriod,
                user: widget.user,
              ),
              _RecordType.quizzes => _QuizRecordsList(
                recordsStream: _quizAttemptsStream(),
                filterRecords: (records) =>
                    _filterByPeriod(records, 'answeredAt'),
              ),
              _RecordType.notes => _LessonNoteRecordsList(
                notesStream: _lessonNotesStream(),
                filterNotes: _filterNotes,
              ),
              _RecordType.comments => _LessonQuestionRecordsList(
                questionsStream: _lessonQuestionsStream(),
                answersStream: _lessonQuestionAnswersStream(),
                filterQuestions: _filterQuestions,
                filterAnswers: _filterAnswers,
                selectedType: _selectedCommentType,
                onSelectedType: (type) {
                  setState(() {
                    _selectedCommentType = type;
                  });
                },
                user: widget.user,
              ),
            },
          ],
        ),
      ),
    );
  }

  List<LessonNote> _filterNotes(List<LessonNote> notes) {
    final since = _periodStart();
    final query = _query.trim().toLowerCase();
    return notes.where((note) {
      if (since != null) {
        final updatedAt = note.updatedAt ?? note.createdAt;
        if (updatedAt == null || updatedAt.toDate().isBefore(since)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return lessonNoteMatchesQuery(note, query);
    }).toList();
  }

  List<LessonQuestion> _filterQuestions(List<LessonQuestion> questions) {
    final since = _periodStart();
    final query = _query.trim().toLowerCase();
    final filtered = questions.where((question) {
      if (question.isDeleted) {
        return false;
      }
      if (since != null) {
        final updatedAt = question.updatedAt ?? question.createdAt;
        if (updatedAt == null || updatedAt.toDate().isBefore(since)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return lessonQuestionMatchesQuery(question, query);
    }).toList();
    filtered.sort(
      (a, b) => _compareTimestampDescWithUnknownLast(
        a.createdAt ?? a.updatedAt,
        b.createdAt ?? b.updatedAt,
      ),
    );
    return filtered;
  }

  List<LessonQuestionAnswer> _filterAnswers(
    List<LessonQuestionAnswer> answers,
  ) {
    final since = _periodStart();
    final query = _query.trim().toLowerCase();
    final filtered = answers.where((answer) {
      if (answer.isDeleted) {
        return false;
      }
      if (since != null) {
        final updatedAt = answer.updatedAt ?? answer.createdAt;
        if (updatedAt == null || updatedAt.toDate().isBefore(since)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return lessonQuestionAnswerMatchesQuery(answer, query);
    }).toList();
    filtered.sort(
      (a, b) => _compareTimestampDescWithUnknownLast(
        a.createdAt ?? a.updatedAt,
        b.createdAt ?? b.updatedAt,
      ),
    );
    return filtered;
  }
}

class _RecordTypeSelector extends StatelessWidget {
  const _RecordTypeSelector({
    required this.selectedType,
    required this.onSelected,
  });

  final _RecordType selectedType;
  final ValueChanged<_RecordType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('視聴記録'),
          selected: selectedType == _RecordType.views,
          onSelected: (_) => onSelected(_RecordType.views),
        ),
        ChoiceChip(
          label: const Text('クイズ回答'),
          selected: selectedType == _RecordType.quizzes,
          onSelected: (_) => onSelected(_RecordType.quizzes),
        ),
        ChoiceChip(
          label: const Text('レッスンメモ'),
          selected: selectedType == _RecordType.notes,
          onSelected: (_) => onSelected(_RecordType.notes),
        ),
        ChoiceChip(
          label: const Text('質問・回答コメントを見る'),
          selected: selectedType == _RecordType.comments,
          onSelected: (_) => onSelected(_RecordType.comments),
        ),
      ],
    );
  }
}

class _PeriodFilterChips extends StatelessWidget {
  const _PeriodFilterChips({
    required this.selectedPeriod,
    required this.onSelected,
  });

  final _PeriodFilter selectedPeriod;
  final ValueChanged<_PeriodFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('すべて'),
          selected: selectedPeriod == _PeriodFilter.all,
          onSelected: (_) => onSelected(_PeriodFilter.all),
        ),
        ChoiceChip(
          label: const Text('今日'),
          selected: selectedPeriod == _PeriodFilter.today,
          onSelected: (_) => onSelected(_PeriodFilter.today),
        ),
        ChoiceChip(
          label: const Text('7日間'),
          selected: selectedPeriod == _PeriodFilter.sevenDays,
          onSelected: (_) => onSelected(_PeriodFilter.sevenDays),
        ),
        ChoiceChip(
          label: const Text('30日間'),
          selected: selectedPeriod == _PeriodFilter.thirtyDays,
          onSelected: (_) => onSelected(_PeriodFilter.thirtyDays),
        ),
      ],
    );
  }
}

class _ViewRecordsList extends StatelessWidget {
  const _ViewRecordsList({
    required this.segmentRecordsStream,
    required this.legacyRecordsStream,
    required this.filterRecords,
    required this.user,
  });

  final Stream<List<Map<String, dynamic>>> segmentRecordsStream;
  final Stream<List<Map<String, dynamic>>> legacyRecordsStream;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>> records)
  filterRecords;
  final User user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: segmentRecordsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final segmentRecords = snapshot.data ?? const [];
        final records = filterRecords(
          _recordsWithDisplayCycleNumbers(
            segmentRecords,
          ).where((record) => record['isDeleted'] != true).toList(),
        );
        if (records.isNotEmpty) {
          return Column(
            children: [
              for (final record in records) ...[
                _ViewSegmentRecordCard(record: record, user: user),
                const SizedBox(height: 12),
              ],
            ],
          );
        }

        if (segmentRecords.isNotEmpty) {
          return const _EmptyRecordCard(message: 'この期間の視聴記録はまだありません。');
        }

        return _LegacyViewRecordsList(
          recordsStream: legacyRecordsStream,
          filterRecords: filterRecords,
        );
      },
    );
  }
}

List<Map<String, dynamic>> _recordsWithDisplayCycleNumbers(
  List<Map<String, dynamic>> records,
) {
  final deletedCyclesByLesson = <String, Set<int>>{};
  final recordsByLessonAndCycle = <String, List<Map<String, dynamic>>>{};

  for (final record in records) {
    final lessonKey = _lessonDisplayKey(record);
    final cycleNumber = _cycleNumberOf(record);
    final cycleKey = '$lessonKey::$cycleNumber';
    recordsByLessonAndCycle.putIfAbsent(cycleKey, () => []).add(record);
  }

  for (final entry in recordsByLessonAndCycle.entries) {
    final cycleRecords = entry.value;
    final isCycleFullyDeleted = cycleRecords.every(
      (record) => record['isDeleted'] == true,
    );
    if (!isCycleFullyDeleted) {
      continue;
    }

    final sampleRecord = cycleRecords.first;
    final lessonKey = _lessonDisplayKey(sampleRecord);
    deletedCyclesByLesson
        .putIfAbsent(lessonKey, () => <int>{})
        .add(_cycleNumberOf(sampleRecord));
  }

  return records.map((record) {
    final lessonKey = _lessonDisplayKey(record);
    final cycleNumber = _cycleNumberOf(record);
    final deletedPreviousCycleCount =
        deletedCyclesByLesson[lessonKey]
            ?.where((deletedCycle) => deletedCycle < cycleNumber)
            .length ??
        0;

    return {...record, 'cycleNumber': cycleNumber - deletedPreviousCycleCount};
  }).toList();
}

String _lessonDisplayKey(Map<String, dynamic> record) {
  final courseId = record['courseId'];
  final lessonNumber = _lessonNumberOf(record);
  if (courseId is String && courseId.isNotEmpty) {
    return 'course:$courseId|lesson:$lessonNumber';
  }

  final courseTitle = record['courseTitle'] as String? ?? '';
  final lessonTitle = record['lessonTitle'] as String? ?? '';
  return 'courseTitle:$courseTitle|lesson:$lessonNumber|lessonTitle:$lessonTitle';
}

int _cycleNumberOf(Map<String, dynamic> record) {
  return (record['cycleNumber'] as num?)?.toInt() ?? 1;
}

int _lessonNumberOf(Map<String, dynamic> record) {
  return (record['lessonNumber'] as num?)?.toInt() ?? 1;
}

class _LegacyViewRecordsList extends StatelessWidget {
  const _LegacyViewRecordsList({
    required this.recordsStream,
    required this.filterRecords,
  });

  final Stream<List<Map<String, dynamic>>> recordsStream;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>> records)
  filterRecords;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: recordsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = filterRecords(snapshot.data ?? const []);
        if (records.isEmpty) {
          return const _EmptyRecordCard(message: 'この期間の視聴記録はまだありません。');
        }

        return Column(
          children: [
            for (final record in records) ...[
              _ViewRecordCard(record: record),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _QuizRecordsList extends StatelessWidget {
  const _QuizRecordsList({
    required this.recordsStream,
    required this.filterRecords,
  });

  final Stream<List<Map<String, dynamic>>> recordsStream;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>> records)
  filterRecords;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: recordsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = filterRecords(snapshot.data ?? const []);
        if (records.isEmpty) {
          return const _EmptyRecordCard(message: 'この期間のクイズ回答記録はまだありません。');
        }

        final correctCount = records
            .where((record) => record['isCorrect'] == true)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('正解数 $correctCount / ${records.length}'),
              ),
            ),
            const SizedBox(height: 12),
            for (final record in records) ...[
              _QuizRecordCard(record: record),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _LessonNoteRecordsList extends StatelessWidget {
  const _LessonNoteRecordsList({
    required this.notesStream,
    required this.filterNotes,
  });

  final Stream<List<LessonNote>> notesStream;
  final List<LessonNote> Function(List<LessonNote> notes) filterNotes;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonNote>>(
      stream: notesStream,
      builder: (context, snapshot) {
        final notes = filterNotes(snapshot.data ?? const []);
        if (notes.isEmpty) {
          return const _EmptyRecordCard(message: 'この期間のレッスンメモはまだありません。');
        }
        return Column(
          children: [
            for (final note in notes) ...[
              _LessonNoteRecordCard(note: note),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _LessonQuestionRecordsList extends StatelessWidget {
  const _LessonQuestionRecordsList({
    required this.questionsStream,
    required this.answersStream,
    required this.filterQuestions,
    required this.filterAnswers,
    required this.selectedType,
    required this.onSelectedType,
    required this.user,
  });

  final Stream<List<LessonQuestion>> questionsStream;
  final Stream<List<LessonQuestionAnswer>> answersStream;
  final List<LessonQuestion> Function(List<LessonQuestion> questions)
  filterQuestions;
  final List<LessonQuestionAnswer> Function(List<LessonQuestionAnswer> answers)
  filterAnswers;
  final _CommentRecordType selectedType;
  final ValueChanged<_CommentRecordType> onSelectedType;
  final User user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonQuestion>>(
      stream: questionsStream,
      builder: (context, questionSnapshot) {
        return StreamBuilder<List<LessonQuestionAnswer>>(
          stream: answersStream,
          builder: (context, answerSnapshot) {
            final allQuestions =
                questionSnapshot.data ?? const <LessonQuestion>[];
            final questions = filterQuestions(allQuestions);
            final answers = filterAnswers(answerSnapshot.data ?? const []);
            final isQuestionSelected =
                selectedType == _CommentRecordType.questions;
            final isEmpty = isQuestionSelected
                ? questions.isEmpty
                : answers.isEmpty;
            if (isEmpty) {
              return Column(
                children: [
                  _CommentTypeSelector(
                    selectedType: selectedType,
                    onSelected: onSelectedType,
                  ),
                  const SizedBox(height: 12),
                  _EmptyRecordCard(
                    message: isQuestionSelected
                        ? 'この期間の質問コメントはまだありません。'
                        : 'この期間の回答コメントはまだありません。',
                  ),
                ],
              );
            }
            return Column(
              children: [
                _CommentTypeSelector(
                  selectedType: selectedType,
                  onSelected: onSelectedType,
                ),
                const SizedBox(height: 12),
                if (isQuestionSelected)
                  for (final question in questions) ...[
                    _LessonQuestionRecordCard(
                      question: question,
                      questions: allQuestions,
                      answers: answers,
                      user: user,
                    ),
                    const SizedBox(height: 12),
                  ]
                else
                  for (final answer in answers) ...[
                    _LessonAnswerRecordCard(
                      answer: answer,
                      user: user,
                      parentQuestion: _parentQuestionForAnswer(
                        answer,
                        allQuestions,
                      ),
                      questions: allQuestions,
                      answers: answers,
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CommentTypeSelector extends StatelessWidget {
  const _CommentTypeSelector({
    required this.selectedType,
    required this.onSelected,
  });

  final _CommentRecordType selectedType;
  final ValueChanged<_CommentRecordType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('質問コメント'),
          selected: selectedType == _CommentRecordType.questions,
          onSelected: (_) => onSelected(_CommentRecordType.questions),
        ),
        ChoiceChip(
          label: const Text('回答コメント'),
          selected: selectedType == _CommentRecordType.answers,
          onSelected: (_) => onSelected(_CommentRecordType.answers),
        ),
      ],
    );
  }
}

LessonQuestion? _parentQuestionForAnswer(
  LessonQuestionAnswer answer,
  List<LessonQuestion> questions,
) {
  for (final question in questions) {
    if (question.id == answer.questionId && !question.isDeleted) {
      return question;
    }
  }
  return null;
}

class _LessonNoteRecordCard extends StatelessWidget {
  const _LessonNoteRecordCard({required this.note});

  final LessonNote note;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.title.isEmpty ? '無題のメモ' : note.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${note.courseTitle} / レッスン${note.lessonNumber}: ${note.lessonTitle}',
            ),
            const SizedBox(height: 4),
            Text(note.isPublic ? '公開メモ' : '非公開メモ'),
            const SizedBox(height: 4),
            Text('更新日: ${_formatTimestamp(note.updatedAt ?? note.createdAt)}'),
            if (note.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(note.body),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LessonNotesPage(
                        course: _courseFromNote(note),
                        lesson: CourseLesson(
                          title: note.lessonTitle,
                          duration: '1分30秒',
                        ),
                        lessonNumber: note.lessonNumber,
                      ),
                    ),
                  );
                },
                child: const Text('メモを開いて編集'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonQuestionRecordCard extends StatelessWidget {
  const _LessonQuestionRecordCard({
    required this.question,
    required this.questions,
    required this.answers,
    required this.user,
  });

  final LessonQuestion question;
  final List<LessonQuestion> questions;
  final List<LessonQuestionAnswer> answers;
  final User user;

  bool get _canOpenQuestionThread => _canOpenQuestionFromRecord(question);
  String? get _unavailableMessage => _canOpenQuestionThread
      ? null
      : 'この質問コメントは削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';

  void _openQuestionThread(BuildContext context) {
    if (!_canOpenQuestionThread) {
      return;
    }
    _openQuestionThreadPage(
      context: context,
      question: question,
      questions: questions,
      answers: answers,
    );
  }

  Future<void> _showDetails(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('質問コメントの記録'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'あなたの質問',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  question.body.isEmpty ? '本文はありません。' : question.body,
                ),
                if ((question.quotedNoteTitle ?? '').isNotEmpty ||
                    (question.quotedNoteBody ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '引用メモ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_quotedNotePreviewText(question)),
                ],
                const SizedBox(height: 16),
                const Text(
                  '公開範囲',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(question.isPublic ? '公開質問' : '先生にだけ公開'),
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

  Future<void> _deleteQuestion() async {
    final questionId = question.id;
    if (questionId == null || Firebase.apps.isEmpty) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final privateRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('lessonQuestions')
        .doc(questionId);
    final publicRef = firestore
        .collection('publicLessonQuestions')
        .doc(questionId);
    final publicSnapshot = await publicRef.get();
    final batch = firestore.batch()
      ..set(privateRef, {
        'isDeleted': true,
        'deletedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
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

  Future<void> _confirmAndDelete(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('質問コメントを削除'),
          content: const Text('この質問コメントを削除しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    try {
      await _deleteQuestion();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('質問コメントを削除しました。')));
    } on FirebaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(error.message ?? '質問コメントの削除に失敗しました。')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        key: ValueKey('question-record-open-${question.id ?? question.body}'),
        onTap: _canOpenQuestionThread
            ? () => _openQuestionThread(context)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '質問コメント',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${question.courseTitle} / レッスン${question.lessonNumber}: ${question.lessonTitle}',
              ),
              const SizedBox(height: 4),
              Text(question.isPublic ? '公開質問' : '先生にだけ公開'),
              const SizedBox(height: 4),
              Text(
                '投稿日: ${_formatCommentTimestamp(question.createdAt ?? question.updatedAt)}',
              ),
              if (question.body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(question.body),
              ],
              if ((question.quotedNoteTitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('引用メモ: ${question.quotedNoteTitle}'),
              ],
              if (_unavailableMessage != null) ...[
                const SizedBox(height: 8),
                Text(_unavailableMessage!),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_canOpenQuestionThread)
                    const Expanded(
                      child: Text(
                        'タップしてコメント欄を開けます。',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: question.id == null
                        ? null
                        : () => _confirmAndDelete(context),
                    child: const Text('削除'),
                  ),
                  TextButton(
                    onPressed: () => _showDetails(context),
                    child: const Text('詳しく見る'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonAnswerRecordCard extends StatefulWidget {
  const _LessonAnswerRecordCard({
    required this.answer,
    required this.user,
    required this.questions,
    required this.answers,
    this.parentQuestion,
  });

  final LessonQuestionAnswer answer;
  final User user;
  final List<LessonQuestion> questions;
  final List<LessonQuestionAnswer> answers;
  final LessonQuestion? parentQuestion;

  @override
  State<_LessonAnswerRecordCard> createState() =>
      _LessonAnswerRecordCardState();
}

class _LessonAnswerRecordCardState extends State<_LessonAnswerRecordCard> {
  late Future<LessonQuestion?> _parentQuestionFuture;
  late Future<LessonQuestionAnswer?> _parentAnswerFuture;

  @override
  void initState() {
    super.initState();
    _parentQuestionFuture = _loadParentQuestion();
    _parentAnswerFuture = _loadParentAnswer();
  }

  @override
  void didUpdateWidget(covariant _LessonAnswerRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.answer.questionId != widget.answer.questionId ||
        oldWidget.parentQuestion != widget.parentQuestion) {
      _parentQuestionFuture = _loadParentQuestion();
    }
    if (oldWidget.answer.parentCommentId != widget.answer.parentCommentId ||
        oldWidget.answer.parentCommentType != widget.answer.parentCommentType ||
        oldWidget.answers != widget.answers) {
      _parentAnswerFuture = _loadParentAnswer();
    }
  }

  bool _canOpenQuestionThreadFor(LessonQuestion? question) {
    return question != null &&
        _canOpenQuestionFromRecord(question) &&
        _canOpenAnswerFromRecord(widget.answer);
  }

  String? _unavailableMessageFor(LessonQuestion? question) {
    if (!_canOpenAnswerFromRecord(widget.answer)) {
      return 'この回答コメントは削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';
    }
    if (question == null || !_canOpenQuestionFromRecord(question)) {
      return '元の質問は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';
    }
    return null;
  }

  bool _shouldHideReplyTargetPreview() {
    if (widget.answer.parentCommentType != 'answer') {
      return false;
    }
    final parentId = widget.answer.parentCommentId;
    if (parentId == null || parentId.isEmpty) {
      return true;
    }
    for (final answer in widget.answers) {
      if (answer.id == parentId) {
        return !_canOpenAnswerFromRecord(answer);
      }
    }
    return true;
  }

  bool _isReplyTargetUnavailable(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (widget.answer.parentCommentType == 'answer') {
      if (parentAnswer == null) {
        return _shouldHideReplyTargetPreview();
      }
      return !_canOpenAnswerFromRecord(parentAnswer);
    }
    return question == null || !_canOpenQuestionFromRecord(question);
  }

  Timestamp? _parentCommentTimestamp(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (widget.answer.parentCommentType == 'answer') {
      if (parentAnswer != null) {
        return parentAnswer.createdAt ?? parentAnswer.updatedAt;
      }
      final parentId = widget.answer.parentCommentId;
      if (parentId == null || parentId.isEmpty) {
        return null;
      }
      for (final answer in widget.answers) {
        if (answer.id == parentId) {
          return answer.createdAt ?? answer.updatedAt;
        }
      }
      return widget.answer.replyToCreatedAt;
    }
    return question?.createdAt ??
        question?.updatedAt ??
        widget.answer.replyToCreatedAt;
  }

  String _replyTargetRecordSummary(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    final replyTo = _safeReplyTargetDisplayName(
      widget.answer.replyToDisplayName,
      role: widget.answer.replyToAuthorRole,
    );
    final replyToRole = (widget.answer.replyToAuthorRole ?? '').trim();
    final replyToLabel = replyTo.isNotEmpty
        ? replyTo
        : replyToRole == 'teacher'
        ? '先生'
        : replyToRole == 'student'
        ? '学習者'
        : '不明';
    final parentTimestamp = _parentCommentTimestamp(question, parentAnswer);
    final repliedAt = widget.answer.createdAt ?? widget.answer.updatedAt;
    final parentTimestampText = parentTimestamp == null
        ? '不明'
        : _formatTimestamp(parentTimestamp);
    final repliedAtText = repliedAt == null
        ? '不明'
        : _formatTimestamp(repliedAt);
    return [
      '1. 誰に対して: $replyToLabel',
      '2. いつ投稿されたコメントに対して: $parentTimestampText',
      '3. いつ自分が返信したか: $repliedAtText',
    ].join('\n');
  }

  void _openQuestionThread(
    BuildContext context,
    LessonQuestion? parentQuestion,
  ) {
    final question = parentQuestion;
    if (question == null || !_canOpenQuestionThreadFor(question)) {
      return;
    }
    _openQuestionThreadPage(
      context: context,
      question: question,
      questions: widget.questions,
      answers: widget.answers,
      highlightedAnswerId: widget.answer.id,
    );
  }

  Future<LessonQuestion?> _loadParentQuestion() async {
    final alreadyLoadedQuestion = widget.parentQuestion;
    if (alreadyLoadedQuestion != null) {
      return alreadyLoadedQuestion;
    }
    if (Firebase.apps.isEmpty || widget.answer.questionId.isEmpty) {
      return null;
    }
    try {
      final privateSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('lessonQuestions')
          .doc(widget.answer.questionId)
          .get();
      if (privateSnapshot.exists) {
        final question = LessonQuestion.fromFirestore(privateSnapshot);
        if (!question.isDeleted) {
          return question;
        }
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('publicLessonQuestions')
          .doc(widget.answer.questionId)
          .get();
      if (!snapshot.exists) {
        return null;
      }
      final question = LessonQuestion.fromFirestore(snapshot);
      return question.isDeleted ? null : question;
    } on FirebaseException {
      return null;
    }
  }

  Future<LessonQuestionAnswer?> _loadParentAnswer() async {
    if (widget.answer.parentCommentType != 'answer') {
      return null;
    }
    final parentId = widget.answer.parentCommentId;
    if (parentId == null || parentId.isEmpty) {
      return null;
    }
    for (final answer in widget.answers) {
      if (answer.id == parentId) {
        return answer;
      }
    }
    if (Firebase.apps.isEmpty) {
      return null;
    }
    try {
      final privateSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('lessonQuestionAnswers')
          .doc(parentId)
          .get();
      if (privateSnapshot.exists) {
        return LessonQuestionAnswer.fromFirestore(privateSnapshot);
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

  Future<void> _showDetails(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return FutureBuilder<LessonQuestion?>(
          future: _parentQuestionFuture,
          builder: (context, snapshot) {
            final parentQuestion = snapshot.data;
            return FutureBuilder<LessonQuestionAnswer?>(
              future: _parentAnswerFuture,
              builder: (context, parentAnswerSnapshot) {
                final parentAnswer = parentAnswerSnapshot.data;
                return AlertDialog(
                  title: const Text('回答コメントの記録'),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'あなたの回答',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(widget.answer.body),
                        const SizedBox(height: 16),
                        const Text(
                          '返信先の控え',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _isReplyTargetUnavailable(parentQuestion, parentAnswer)
                              ? _replyTargetRecordSummary(
                                  parentQuestion,
                                  parentAnswer,
                                )
                              : _replyPreviewText(
                                  widget.answer,
                                  hideBodyPreview: false,
                                ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '元の質問',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Text('確認中です...')
                        else if (parentQuestion == null)
                          const Text('元の質問は削除済み、または現在は表示できません。')
                        else
                          SelectableText(parentQuestion.body),
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
          },
        );
      },
    );
  }

  Future<void> _deleteAnswer() async {
    final answerId = widget.answer.id;
    if (answerId == null || Firebase.apps.isEmpty) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final deletedData = {
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final privateRef = firestore
        .collection('users')
        .doc(widget.user.uid)
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

  Future<void> _confirmAndDelete(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('回答コメントを削除'),
          content: const Text('この回答コメントを削除しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    try {
      await _deleteAnswer();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('回答コメントを削除しました。')));
    } on FirebaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(error.message ?? '回答コメントの削除に失敗しました。')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LessonQuestion?>(
      future: _parentQuestionFuture,
      builder: (context, snapshot) {
        final loadedParentQuestion = snapshot.data;
        final canOpenQuestionThread = _canOpenQuestionThreadFor(
          loadedParentQuestion,
        );
        final unavailableMessage =
            snapshot.connectionState == ConnectionState.waiting &&
                _canOpenAnswerFromRecord(widget.answer)
            ? null
            : _unavailableMessageFor(loadedParentQuestion);
        return FutureBuilder<LessonQuestionAnswer?>(
          future: _parentAnswerFuture,
          builder: (context, parentAnswerSnapshot) {
            final parentAnswer = parentAnswerSnapshot.data;
            final replyPreview =
                _isReplyTargetUnavailable(loadedParentQuestion, parentAnswer)
                ? _replyTargetRecordSummary(loadedParentQuestion, parentAnswer)
                : _replyPreviewText(widget.answer, hideBodyPreview: false);
            return Card(
              child: InkWell(
                key: ValueKey(
                  'answer-record-open-${widget.answer.id ?? widget.answer.body}',
                ),
                onTap: canOpenQuestionThread
                    ? () => _openQuestionThread(context, loadedParentQuestion)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '回答コメント',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.answer.courseTitle} / レッスン${widget.answer.lessonNumber}: ${widget.answer.lessonTitle}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '投稿日: ${_formatCommentTimestamp(widget.answer.createdAt ?? widget.answer.updatedAt)}',
                      ),
                      const SizedBox(height: 8),
                      Text(widget.answer.body),
                      const SizedBox(height: 8),
                      Text('返信先の控え:\n$replyPreview'),
                      if (unavailableMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(unavailableMessage),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (canOpenQuestionThread)
                            const Expanded(
                              child: Text(
                                'タップしてコメント欄を開けます。',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          else
                            const Spacer(),
                          TextButton(
                            onPressed: widget.answer.id == null
                                ? null
                                : () => _confirmAndDelete(context),
                            child: const Text('削除'),
                          ),
                          TextButton(
                            key: ValueKey(
                              'answer-record-details-${widget.answer.id ?? widget.answer.body}',
                            ),
                            onPressed: () => _showDetails(context),
                            child: const Text('詳しく見る'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

bool _canOpenQuestionFromRecord(LessonQuestion question) {
  return !question.isDeleted && !question.isTeacherHidden;
}

bool _canOpenAnswerFromRecord(LessonQuestionAnswer answer) {
  return !answer.isDeleted &&
      answer.moderationStatus != lessonInteractionModerationHiddenByTeacher;
}

void _openQuestionThreadPage({
  required BuildContext context,
  required LessonQuestion question,
  required List<LessonQuestion> questions,
  required List<LessonQuestionAnswer> answers,
  String? highlightedAnswerId,
}) {
  final useRecordStreams = Firebase.apps.isEmpty;
  final recordQuestionsStream = useRecordStreams
      ? Stream.value(questions).asBroadcastStream()
      : null;
  final recordPublicQuestionsStream = useRecordStreams
      ? Stream.value(const <LessonQuestion>[]).asBroadcastStream()
      : null;
  final recordAnswersStream = useRecordStreams
      ? Stream.value(
          answers
              .where((answer) => answer.questionId == question.id)
              .where(_canOpenAnswerFromRecord)
              .toList(),
        ).asBroadcastStream()
      : null;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('質問コメント')),
        body: SafeArea(
          child: LessonQuestionsPanel(
            course: _courseFromQuestion(question),
            lesson: CourseLesson(
              title: question.lessonTitle,
              duration: '1分30秒',
            ),
            lessonNumber: question.lessonNumber,
            initialSelectedQuestion: question,
            questionsStream: recordQuestionsStream,
            publicQuestionsStream: recordPublicQuestionsStream,
            answersStream: recordAnswersStream,
            initialHighlightedAnswerId: highlightedAnswerId,
          ),
        ),
      ),
    ),
  );
}

Course _courseFromQuestion(LessonQuestion question) {
  return Course(
    id: question.courseId,
    title: question.courseTitle,
    instructorName: '',
    category: '',
    level: '',
    duration: '',
    lessonCount: question.lessonNumber,
    rating: 0,
    priceLabel: '',
    description: '',
    lessons: [CourseLesson(title: question.lessonTitle, duration: '1分30秒')],
  );
}

String _replyPreviewText(
  LessonQuestionAnswer answer, {
  bool hideBodyPreview = false,
}) {
  final displayName = _safeReplyTargetDisplayName(
    answer.replyToDisplayName,
    role: answer.replyToAuthorRole,
  );
  final bodyPreview = hideBodyPreview
      ? null
      : answer.replyToBodyPreview?.trim();
  if (displayName.isEmpty && (bodyPreview ?? '').isEmpty) {
    return '返信先の控えはありません。';
  }
  if (displayName.isEmpty) {
    return bodyPreview!;
  }
  if ((bodyPreview ?? '').isEmpty) {
    return '$displayName への返信';
  }
  return '$displayName の「$bodyPreview」への返信';
}

String _safeReplyTargetDisplayName(String? value, {String? role}) {
  final text = (value ?? '').trim();
  if (text.isNotEmpty && !_looksLikeEmail(text)) {
    return text;
  }
  if (role == 'teacher') {
    return '先生';
  }
  if (role == 'student') {
    return '学習者';
  }
  return '';
}

bool _looksLikeEmail(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return false;
  }
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
}

String _quotedNotePreviewText(LessonQuestion question) {
  final title = question.quotedNoteTitle?.trim();
  final body = question.quotedNoteBody?.trim();
  if ((title ?? '').isEmpty && (body ?? '').isEmpty) {
    return '引用メモはありません。';
  }
  if ((title ?? '').isEmpty) {
    return body!;
  }
  if ((body ?? '').isEmpty) {
    return title!;
  }
  return '$title\n$body';
}

Course _courseFromNote(LessonNote note) {
  return Course(
    id: note.courseId,
    title: note.courseTitle,
    instructorName: '',
    category: '',
    level: '',
    duration: '',
    lessonCount: note.lessonNumber,
    rating: 0,
    priceLabel: '',
    description: '',
    lessons: [CourseLesson(title: note.lessonTitle, duration: '1分30秒')],
  );
}

class _ViewRecordCard extends StatelessWidget {
  const _ViewRecordCard({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('視聴記録', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(record['courseTitle'] as String? ?? '講座名未設定'),
            const SizedBox(height: 4),
            Text('レッスン: ${record['lessonTitle'] as String? ?? '未設定'}'),
            const SizedBox(height: 4),
            Text('日時: ${_formatTimestamp(record['createdAt'])}'),
          ],
        ),
      ),
    );
  }
}

class _ViewSegmentRecordCard extends StatelessWidget {
  const _ViewSegmentRecordCard({required this.record, required this.user});

  final Map<String, dynamic> record;
  final User user;

  Future<void> _deleteRecord() async {
    final segmentId = record['id'] as String?;
    if (segmentId == null || Firebase.apps.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonViewSegments')
        .doc(segmentId)
        .set({
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final lessonNumber = (record['lessonNumber'] as num?)?.toInt() ?? 1;
    final cycleNumber = (record['cycleNumber'] as num?)?.toInt() ?? 1;
    final isCompleted = record['status'] == 'completed';
    final studySeconds = (record['studySeconds'] as num?)?.toInt() ?? 0;
    final watchSeconds = (record['watchSeconds'] as num?)?.toInt() ?? 0;
    final timestamp = isCompleted ? record['completedAt'] : record['startedAt'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCompleted
                  ? 'レッスン$lessonNumber $cycleNumber周目終了'
                  : 'レッスン$lessonNumber $cycleNumber周目',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(record['courseTitle'] as String? ?? '講座名未設定'),
            const SizedBox(height: 4),
            Text('レッスン: ${record['lessonTitle'] as String? ?? '未設定'}'),
            const SizedBox(height: 4),
            Text(
              isCompleted
                  ? '終了日時: ${_formatTimestamp(timestamp)}'
                  : '開始日時: ${_formatTimestamp(timestamp)}',
            ),
            const SizedBox(height: 4),
            Text('学習時間: $studySeconds秒'),
            const SizedBox(height: 4),
            Text('視聴時間: $watchSeconds秒'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _deleteRecord,
                icon: const Icon(Icons.delete_outline),
                label: const Text('この視聴記録を削除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizRecordCard extends StatelessWidget {
  const _QuizRecordCard({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final isCorrect = record['isCorrect'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCorrect ? '正解' : '不正解',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCorrect
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(record['courseTitle'] as String? ?? '講座名未設定'),
            const SizedBox(height: 4),
            Text('レッスン: ${record['lessonTitle'] as String? ?? '未設定'}'),
            const SizedBox(height: 8),
            Text(record['question'] as String? ?? '問題文未設定'),
            const SizedBox(height: 4),
            Text('回答日時: ${_formatTimestamp(record['answeredAt'])}'),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecordCard extends StatelessWidget {
  const _EmptyRecordCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

int _compareTimestampDescWithUnknownLast(Timestamp? a, Timestamp? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return b.toDate().compareTo(a.toDate());
}

String _formatCommentTimestamp(Timestamp? timestamp) {
  if (timestamp == null) {
    return '不明';
  }
  return _formatTimestamp(timestamp);
}

String _formatTimestamp(Object? value) {
  if (value is! Timestamp) {
    return '日時未設定';
  }

  final date = value.toDate();
  final year = date.year.toString();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$year/$month/$day $hour:$minute';
}
