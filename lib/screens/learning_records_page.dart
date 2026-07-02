import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';
import '../models/course_profile_display.dart';
import '../models/public_user_profile.dart';
import '../services/lesson_interaction_service.dart';
import 'lesson_notes_page.dart';
import 'lesson_questions_page.dart';

class LearningRecordsPage extends StatefulWidget {
  const LearningRecordsPage({
    super.key,
    required this.user,
    this.activeCommentRole,
    this.learningEventsStream,
    this.lessonViewSegmentsStream,
    this.quizAttemptsStream,
    this.lessonNotesStream,
    this.lessonQuestionsStream,
    this.lessonQuestionAnswersStream,
    this.questionPublicEnabledResolver,
  });

  final User user;
  final String? activeCommentRole;
  final Stream<List<Map<String, dynamic>>>? learningEventsStream;
  final Stream<List<Map<String, dynamic>>>? lessonViewSegmentsStream;
  final Stream<List<Map<String, dynamic>>>? quizAttemptsStream;
  final Stream<List<LessonNote>>? lessonNotesStream;
  final Stream<List<LessonQuestion>>? lessonQuestionsStream;
  final Stream<List<LessonQuestionAnswer>>? lessonQuestionAnswersStream;
  final Future<bool> Function(LessonQuestion question)?
  questionPublicEnabledResolver;

  @override
  State<LearningRecordsPage> createState() => _LearningRecordsPageState();
}

enum _RecordType { views, quizzes, notes, comments }

enum _PeriodFilter { all, today, sevenDays, thirtyDays }

enum _CommentRecordType { questions, answers }

const String _recordRoleMismatchDeleteMessage =
    'この立場で作成したコメントではないため、ここからは削除できません。';

String _normalizedRecordCommentRole(String? role) {
  final normalized = (role ?? '').trim();
  if (normalized == publicUserProfileRoleTeacher) {
    return publicUserProfileRoleTeacher;
  }
  return publicUserProfileRoleStudent;
}

bool _matchesRecordCommentRole({
  required String currentRole,
  required String? authorRole,
}) {
  return _normalizedRecordCommentRole(authorRole) == currentRole;
}

class _LearningRecordsPageState extends State<LearningRecordsPage> {
  _RecordType _selectedType = _RecordType.views;
  _PeriodFilter _selectedPeriod = _PeriodFilter.all;
  _CommentRecordType _selectedCommentType = _CommentRecordType.questions;
  LessonQuestionSort _commentSort = LessonQuestionSort.newest;
  String _query = '';
  String get _currentCommentRole =>
      _normalizedRecordCommentRole(widget.activeCommentRole);

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
                currentCommentRole: _currentCommentRole,
                selectedType: _selectedCommentType,
                onSelectedType: (type) {
                  setState(() {
                    _selectedCommentType = type;
                  });
                },
                selectedSort: _commentSort,
                onSelectedSort: (sort) {
                  setState(() {
                    _commentSort = sort;
                  });
                },
                user: widget.user,
                questionPublicEnabledResolver:
                    widget.questionPublicEnabledResolver,
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
    final filtered = notes.where((note) {
      if (since != null) {
        final postedAt = lessonNotePostedAt(note);
        if (postedAt == null || postedAt.toDate().isBefore(since)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return lessonNoteMatchesQuery(note, query);
    }).toList();
    filtered.sort(
      (a, b) => _compareTimestampDescWithUnknownLast(
        lessonNotePostedAt(a),
        lessonNotePostedAt(b),
      ),
    );
    return filtered;
  }

  List<LessonQuestion> _filterQuestions(List<LessonQuestion> questions) {
    final since = _periodStart();
    final query = _query.trim().toLowerCase();
    final filtered = questions.where((question) {
      if (question.isDeleted) {
        return false;
      }
      if (!_matchesRecordCommentRole(
        currentRole: _currentCommentRole,
        authorRole: question.authorRole,
      )) {
        return false;
      }
      if (since != null) {
        final referenceTime = _commentSort == LessonQuestionSort.editedNewest
            ? lessonQuestionEditedAt(question)
            : lessonQuestionPostedAt(question);
        if (referenceTime == null || referenceTime.toDate().isBefore(since)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return lessonQuestionMatchesQuery(question, query);
    }).toList();
    filtered.sort((a, b) {
      switch (_commentSort) {
        case LessonQuestionSort.newest:
        case LessonQuestionSort.popular:
          return _compareTimestampDescWithUnknownLast(
            lessonQuestionPostedAt(a),
            lessonQuestionPostedAt(b),
          );
        case LessonQuestionSort.editedNewest:
          return _compareTimestampDescWithUnknownLast(
            lessonQuestionEditedAt(a),
            lessonQuestionEditedAt(b),
          );
      }
    });
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
      if (!_matchesRecordCommentRole(
        currentRole: _currentCommentRole,
        authorRole: answer.authorRole,
      )) {
        return false;
      }
      if (since != null) {
        final referenceTime = _commentSort == LessonQuestionSort.editedNewest
            ? lessonQuestionAnswerEditedAt(answer)
            : lessonQuestionAnswerPostedAt(answer);
        if (referenceTime == null || referenceTime.toDate().isBefore(since)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return lessonQuestionAnswerMatchesQuery(answer, query);
    }).toList();
    filtered.sort((a, b) {
      switch (_commentSort) {
        case LessonQuestionSort.newest:
        case LessonQuestionSort.popular:
          return _compareTimestampDescWithUnknownLast(
            lessonQuestionAnswerPostedAt(a),
            lessonQuestionAnswerPostedAt(b),
          );
        case LessonQuestionSort.editedNewest:
          return _compareTimestampDescWithUnknownLast(
            lessonQuestionAnswerEditedAt(a),
            lessonQuestionAnswerEditedAt(b),
          );
      }
    });
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
    required this.currentCommentRole,
    required this.selectedType,
    required this.onSelectedType,
    required this.selectedSort,
    required this.onSelectedSort,
    required this.user,
    this.questionPublicEnabledResolver,
  });

  final Stream<List<LessonQuestion>> questionsStream;
  final Stream<List<LessonQuestionAnswer>> answersStream;
  final List<LessonQuestion> Function(List<LessonQuestion> questions)
  filterQuestions;
  final List<LessonQuestionAnswer> Function(List<LessonQuestionAnswer> answers)
  filterAnswers;
  final String currentCommentRole;
  final _CommentRecordType selectedType;
  final ValueChanged<_CommentRecordType> onSelectedType;
  final LessonQuestionSort selectedSort;
  final ValueChanged<LessonQuestionSort> onSelectedSort;
  final User user;
  final Future<bool> Function(LessonQuestion question)?
  questionPublicEnabledResolver;

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
                  const SizedBox(height: 8),
                  _CommentSortSelector(
                    selectedSort: selectedSort,
                    onSelected: onSelectedSort,
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
                const SizedBox(height: 8),
                _CommentSortSelector(
                  selectedSort: selectedSort,
                  onSelected: onSelectedSort,
                ),
                const SizedBox(height: 12),
                if (isQuestionSelected)
                  for (final question in questions) ...[
                    _LessonQuestionRecordCard(
                      question: question,
                      questions: allQuestions,
                      answers: answers,
                      user: user,
                      currentCommentRole: currentCommentRole,
                      questionPublicEnabledResolver:
                          questionPublicEnabledResolver,
                    ),
                    const SizedBox(height: 12),
                  ]
                else
                  for (final answer in answers) ...[
                    _LessonAnswerRecordCard(
                      answer: answer,
                      user: user,
                      currentCommentRole: currentCommentRole,
                      parentQuestion: _parentQuestionForAnswer(
                        answer,
                        allQuestions,
                      ),
                      questions: allQuestions,
                      answers: answers,
                      questionPublicEnabledResolver:
                          questionPublicEnabledResolver,
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

class _CommentSortSelector extends StatelessWidget {
  const _CommentSortSelector({
    required this.selectedSort,
    required this.onSelected,
  });

  final LessonQuestionSort selectedSort;
  final ValueChanged<LessonQuestionSort> onSelected;

  @override
  Widget build(BuildContext context) {
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

bool _canIgnorePublicMirrorDeleteError(FirebaseException error) {
  return error.code == 'permission-denied' || error.code == 'not-found';
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
            Text(
              note.isPublic
                  ? '公開メモ'
                  : note.isTeacherOnly
                  ? '先生にだけ公開'
                  : '非公開メモ',
            ),
            const SizedBox(height: 4),
            Text('投稿日: ${_formatCommentTimestamp(lessonNotePostedAt(note))}'),
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
    required this.currentCommentRole,
    this.questionPublicEnabledResolver,
  });

  final LessonQuestion question;
  final List<LessonQuestion> questions;
  final List<LessonQuestionAnswer> answers;
  final User user;
  final String currentCommentRole;
  final Future<bool> Function(LessonQuestion question)?
  questionPublicEnabledResolver;
  bool get _isQuestionInCurrentRole => _matchesRecordCommentRole(
    currentRole: currentCommentRole,
    authorRole: question.authorRole,
  );

  bool get _canOpenQuestionThread => _canOpenQuestionFromRecord(question);
  String? get _unavailableMessage => _canOpenQuestionThread
      ? null
      : 'この質問コメントは削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';

  Future<void> _openQuestionThread(BuildContext context) async {
    if (!_canOpenQuestionThread) {
      return;
    }
    await _openQuestionThreadPage(
      context: context,
      question: question,
      questions: questions,
      answers: answers,
      questionPublicEnabledResolver: questionPublicEnabledResolver,
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
                if (hasQuotedNoteAttachment(
                  quotedNoteId: question.quotedNoteId,
                  quotedNoteTitle: question.quotedNoteTitle,
                  quotedNoteBody: question.quotedNoteBody,
                )) ...[
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

  Future<bool> _deleteQuestion() async {
    final questionId = question.id;
    if (questionId == null || Firebase.apps.isEmpty) {
      return false;
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
    await privateRef.set({
      'isDeleted': true,
      'deletedAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
    try {
      await publicRef.update({
        'studentVisibility': lessonQuestionVisibilityTeacherOnly,
        'isDeleted': true,
        'deletedAt': now,
        'updatedAt': now,
      });
      return false;
    } on FirebaseException catch (error) {
      if (_canIgnorePublicMirrorDeleteError(error)) {
        return true;
      }
      rethrow;
    }
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    if (!_isQuestionInCurrentRole) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text(_recordRoleMismatchDeleteMessage)),
        );
      return;
    }
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
      final skippedPublicMirror = await _deleteQuestion();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              skippedPublicMirror
                  ? '質問コメントを削除しました。古い公開データへの反映は遅れる場合があります。'
                  : '質問コメントを削除しました。',
            ),
          ),
        );
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
                '投稿日: ${_formatCommentTimestamp(lessonQuestionPostedAt(question))}',
              ),
              if (question.body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(question.body),
              ],
              if (hasQuotedNoteAttachment(
                quotedNoteId: question.quotedNoteId,
                quotedNoteTitle: question.quotedNoteTitle,
                quotedNoteBody: question.quotedNoteBody,
              )) ...[
                const SizedBox(height: 8),
                Text(
                  '引用メモ: ${quotedNoteDisplayTitle(
                    quotedNoteId: question.quotedNoteId,
                    quotedNoteTitle: question.quotedNoteTitle,
                  )}',
                ),
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
    required this.currentCommentRole,
    required this.questions,
    required this.answers,
    this.parentQuestion,
    this.questionPublicEnabledResolver,
  });

  final LessonQuestionAnswer answer;
  final User user;
  final String currentCommentRole;
  final List<LessonQuestion> questions;
  final List<LessonQuestionAnswer> answers;
  final LessonQuestion? parentQuestion;
  final Future<bool> Function(LessonQuestion question)?
  questionPublicEnabledResolver;

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

  bool _isQuestionOpenable(LessonQuestion? question) {
    return question != null && _canOpenQuestionFromRecord(question);
  }

  bool _isRecordAnswerOpenable() {
    return _canOpenAnswerFromRecord(widget.answer, allowTeacherHidden: true);
  }

  LessonQuestionAnswer? _effectiveParentAnswer(
    LessonQuestionAnswer? parentAnswer,
  ) {
    return parentAnswer ?? _cachedParentAnswerFromList();
  }

  bool _isParentAnswerOpenable(LessonQuestionAnswer? parentAnswer) {
    final resolvedParentAnswer = _effectiveParentAnswer(parentAnswer);
    return resolvedParentAnswer != null &&
        _canOpenAnswerFromRecord(resolvedParentAnswer);
  }

  bool _isReplyTargetOpenable(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (widget.answer.parentCommentType == 'answer') {
      return _isParentAnswerOpenable(parentAnswer);
    }
    return _isQuestionOpenable(question);
  }

  bool _futureContextAllowsLinkAndNavigation(LessonQuestion? question) {
    // Future gates for course deletion/private/suspension states are wired
    // here so both linkability and thread navigation share one decision point.
    // Until those states are persisted on learning records, keep defaults safe.
    final courseAccessible = question != null;
    final interactionFeatureEnabled = question != null;
    const currentUserActiveInCourse = true;
    const targetUserActiveInCourse = true;
    return courseAccessible &&
        interactionFeatureEnabled &&
        currentUserActiveInCourse &&
        targetUserActiveInCourse;
  }

  bool _canOpenThreadGate(LessonQuestion? question, LessonQuestionAnswer? _) {
    if (!_futureContextAllowsLinkAndNavigation(question)) {
      return false;
    }
    if (!_isQuestionOpenable(question)) {
      return false;
    }
    if (!_isRecordAnswerOpenable()) {
      return false;
    }
    // Product decision: learners can reopen the thread from records as long as
    // the parent question is openable, even when the immediate parent answer
    // is deleted/hidden/unavailable.
    // This keeps "question-level continuity" for old replies.
    return true;
  }

  bool _canOpenQuestionThreadFor(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    return _canOpenThreadGate(question, parentAnswer);
  }

  LessonQuestionAnswer? _cachedParentAnswerFromList() {
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
    return null;
  }

  String? _unavailableMessageFor(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (!_isRecordAnswerOpenable()) {
      return 'この回答コメントは削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';
    }
    if (!_isQuestionOpenable(question)) {
      return '元の質問は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';
    }
    if (widget.answer.parentCommentType == 'answer' &&
        !_isParentAnswerOpenable(parentAnswer)) {
      return '返信先の回答は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。';
    }
    return null;
  }

  bool _isReplyTargetUnavailable(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    return !_isReplyTargetOpenable(question, parentAnswer);
  }

  String? _latestReplyTargetBodyPreview(
    LessonQuestion? question,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (widget.answer.parentCommentType == 'answer') {
      final resolvedParentAnswer = _effectiveParentAnswer(parentAnswer);
      if (!_isParentAnswerOpenable(resolvedParentAnswer)) {
        return null;
      }
      final body = (resolvedParentAnswer?.body ?? '').trim();
      if (body.isEmpty) {
        return null;
      }
      return _shortReplyPreview(body);
    }
    if (!_isQuestionOpenable(question)) {
      return null;
    }
    final body = (question?.body ?? '').trim();
    if (body.isEmpty) {
      return null;
    }
    return _shortReplyPreview(body);
  }

  String? _usableDisplayNameOrNull(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || _looksLikeEmail(text)) {
      return null;
    }
    return text;
  }

  String? _replyTimeDisplayNameOrNull() {
    return _usableDisplayNameOrNull(widget.answer.replyToDisplayName);
  }

  String? _parentPostedDisplayNameOrNull(
    LessonQuestion? parentQuestion,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (widget.answer.parentCommentType == 'answer') {
      return _usableDisplayNameOrNull(
        _effectiveParentAnswer(parentAnswer)?.authorName,
      );
    }
    return _usableDisplayNameOrNull(parentQuestion?.authorName);
  }

  bool _canLinkLatestReplyTargetName(
    LessonQuestion? parentQuestion,
    LessonQuestionAnswer? parentAnswer,
  ) {
    if (!_futureContextAllowsLinkAndNavigation(parentQuestion)) {
      return false;
    }
    if (!_isReplyTargetOpenable(parentQuestion, parentAnswer)) {
      return false;
    }
    final role = (widget.answer.replyToAuthorRole ?? '').trim();
    if (role == publicUserProfileRoleTeacher) {
      return true;
    }
    if (role != publicUserProfileRoleStudent) {
      return false;
    }
    if (widget.answer.parentCommentType == 'answer') {
      return _effectiveParentAnswer(parentAnswer)?.authorProfileVisible == true;
    }
    return parentQuestion?.authorProfileVisible == true;
  }

  String _fallbackReplyTargetDisplayName(
    LessonQuestion? parentQuestion,
    LessonQuestionAnswer? parentAnswer,
  ) {
    final replyTime = _replyTimeDisplayNameOrNull();
    if (replyTime != null) {
      return replyTime;
    }
    final parentPosted = _parentPostedDisplayNameOrNull(
      parentQuestion,
      parentAnswer,
    );
    if (parentPosted != null) {
      return parentPosted;
    }
    return _safeReplyTargetDisplayName(
      null,
      role: widget.answer.replyToAuthorRole,
    );
  }

  Stream<String?> _linkedReplyTargetDisplayNameStream(
    LessonQuestion? parentQuestion,
    LessonQuestionAnswer? parentAnswer, {
    required String fallbackDisplayName,
  }) {
    final safeAuthorId = (widget.answer.replyToAuthorId ?? '').trim();
    if (Firebase.apps.isEmpty ||
        safeAuthorId.isEmpty ||
        !_canLinkLatestReplyTargetName(parentQuestion, parentAnswer)) {
      return Stream.value(null);
    }
    final profileRole =
        (widget.answer.replyToAuthorRole ?? '').trim() ==
            publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    return authorPublicProfileStream(
      courseId: widget.answer.courseId,
      authorId: safeAuthorId,
      authorRole: profileRole,
      authorProfileVisible: true,
      fallbackDisplayName: fallbackDisplayName,
    ).map((profile) {
      final linked = _usableDisplayNameOrNull(profile.displayName);
      return linked;
    });
  }

  Widget _buildReplyPreviewWidget(
    LessonQuestion? parentQuestion,
    LessonQuestionAnswer? parentAnswer, {
    required bool isReplyTargetUnavailable,
    required bool selectable,
  }) {
    final fallbackDisplayName = _fallbackReplyTargetDisplayName(
      parentQuestion,
      parentAnswer,
    );
    return StreamBuilder<String?>(
      stream: _linkedReplyTargetDisplayNameStream(
        parentQuestion,
        parentAnswer,
        fallbackDisplayName: fallbackDisplayName,
      ),
      builder: (context, snapshot) {
        final resolvedDisplayName = _safeReplyTargetDisplayName(
          snapshot.data ?? fallbackDisplayName,
          role: widget.answer.replyToAuthorRole,
        );
        final latestBodyPreview = _latestReplyTargetBodyPreview(
          parentQuestion,
          parentAnswer,
        );
        final previewText = isReplyTargetUnavailable
            ? '$resolvedDisplayName への返信\n現在は見ることができません。'
            : _replyPreviewText(
                widget.answer,
                hideBodyPreview: false,
                overrideDisplayName: resolvedDisplayName,
                overrideBodyPreview: latestBodyPreview,
              );
        if (selectable) {
          return SelectableText(previewText);
        }
        return Text(previewText);
      },
    );
  }

  Future<void> _openQuestionThread(
    BuildContext context,
    LessonQuestion? parentQuestion,
    LessonQuestionAnswer? parentAnswer,
  ) async {
    if (parentQuestion == null) {
      return;
    }
    if (!_canOpenQuestionThreadFor(parentQuestion, parentAnswer)) {
      return;
    }
    await _openQuestionThreadPage(
      context: context,
      question: parentQuestion,
      questions: widget.questions,
      answers: widget.answers,
      highlightedAnswerId: widget.answer.id,
      questionPublicEnabledResolver: widget.questionPublicEnabledResolver,
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
                final isReplyTargetUnavailable = _isReplyTargetUnavailable(
                  parentQuestion,
                  parentAnswer,
                );
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
                        _buildReplyPreviewWidget(
                          parentQuestion,
                          parentAnswer,
                          isReplyTargetUnavailable: isReplyTargetUnavailable,
                          selectable: true,
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

  Future<bool> _deleteAnswer() async {
    final answerId = widget.answer.id;
    if (answerId == null || Firebase.apps.isEmpty) {
      return false;
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
    await privateRef.set(deletedData, SetOptions(merge: true));
    try {
      await publicRef.update(deletedData);
      return false;
    } on FirebaseException catch (error) {
      if (_canIgnorePublicMirrorDeleteError(error)) {
        return true;
      }
      rethrow;
    }
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final isAnswerInCurrentRole = _matchesRecordCommentRole(
      currentRole: widget.currentCommentRole,
      authorRole: widget.answer.authorRole,
    );
    if (!isAnswerInCurrentRole) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text(_recordRoleMismatchDeleteMessage)),
        );
      return;
    }
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
      final skippedPublicMirror = await _deleteAnswer();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              skippedPublicMirror
                  ? '回答コメントを削除しました。古い公開データへの反映は遅れる場合があります。'
                  : '回答コメントを削除しました。',
            ),
          ),
        );
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
        return FutureBuilder<LessonQuestionAnswer?>(
          future: _parentAnswerFuture,
          builder: (context, parentAnswerSnapshot) {
            final parentAnswer =
                parentAnswerSnapshot.data ?? _cachedParentAnswerFromList();
            final canOpenQuestionThread = _canOpenQuestionThreadFor(
              loadedParentQuestion,
              parentAnswer,
            );
            final unavailableMessage =
                (snapshot.connectionState == ConnectionState.waiting ||
                        parentAnswerSnapshot.connectionState ==
                            ConnectionState.waiting) &&
                    _isRecordAnswerOpenable()
                ? null
                : _unavailableMessageFor(loadedParentQuestion, parentAnswer);
            final isReplyTargetUnavailable = _isReplyTargetUnavailable(
              loadedParentQuestion,
              parentAnswer,
            );
            return Card(
              child: InkWell(
                key: ValueKey(
                  'answer-record-open-${widget.answer.id ?? widget.answer.body}',
                ),
                onTap: canOpenQuestionThread
                    ? () => _openQuestionThread(
                        context,
                        loadedParentQuestion,
                        parentAnswer,
                      )
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
                        '投稿日: ${_formatCommentTimestamp(lessonQuestionAnswerPostedAt(widget.answer))}',
                      ),
                      const SizedBox(height: 8),
                      Text(widget.answer.body),
                      const SizedBox(height: 8),
                      const Text('返信先の控え:'),
                      _buildReplyPreviewWidget(
                        loadedParentQuestion,
                        parentAnswer,
                        isReplyTargetUnavailable: isReplyTargetUnavailable,
                        selectable: false,
                      ),
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

bool _canOpenAnswerFromRecord(
  LessonQuestionAnswer answer, {
  bool allowTeacherHidden = false,
}) {
  if (answer.isDeleted) {
    return false;
  }
  if (answer.moderationStatus == lessonInteractionModerationHiddenByTeacher) {
    return allowTeacherHidden;
  }
  return true;
}

const String _publicQuestionThreadDisabledMessage =
    '先生により、このレッスンの公開質問欄は非公開化されています。';

Future<bool> _isQuestionThreadNavigationAllowed({
  required LessonQuestion question,
  Future<bool> Function(LessonQuestion question)? questionPublicEnabledResolver,
}) async {
  if (!question.isPublic) {
    return true;
  }
  if (questionPublicEnabledResolver != null) {
    try {
      return await questionPublicEnabledResolver(question);
    } catch (_) {
      return true;
    }
  }
  return const LessonInteractionService().isPublicFeatureEnabled(
    courseId: question.courseId,
    lessonNumber: question.lessonNumber,
    fieldName: LessonInteractionService.lessonQuestionsPublicEnabledField,
  );
}

Future<LessonQuestion?> _resolveLatestQuestionForThreadNavigation(
  LessonQuestion question,
) async {
  if (question.id == null || Firebase.apps.isEmpty) {
    return _canOpenQuestionFromRecord(question) ? question : null;
  }
  try {
    final publicSnapshot = await FirebaseFirestore.instance
        .collection('publicLessonQuestions')
        .doc(question.id)
        .get();
    if (publicSnapshot.exists) {
      final publicQuestion = LessonQuestion.fromFirestore(publicSnapshot);
      return _canOpenQuestionFromRecord(publicQuestion) ? publicQuestion : null;
    }
  } on FirebaseException {
    // Keep fallback below.
  }
  return _canOpenQuestionFromRecord(question) ? question : null;
}

Future<void> _openQuestionThreadPage({
  required BuildContext context,
  required LessonQuestion question,
  required List<LessonQuestion> questions,
  required List<LessonQuestionAnswer> answers,
  String? highlightedAnswerId,
  Future<bool> Function(LessonQuestion question)? questionPublicEnabledResolver,
}) async {
  final latestQuestion = await _resolveLatestQuestionForThreadNavigation(
    question,
  );
  if (latestQuestion == null) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('元の質問は削除済み、または現在は表示できません。')));
    return;
  }
  final canOpenQuestionThread = await _isQuestionThreadNavigationAllowed(
    question: latestQuestion,
    questionPublicEnabledResolver: questionPublicEnabledResolver,
  );
  if (!canOpenQuestionThread) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text(_publicQuestionThreadDisabledMessage)),
      );
    return;
  }
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
              .where((answer) => answer.questionId == latestQuestion.id)
              .where(
                (answer) =>
                    _canOpenAnswerFromRecord(answer) ||
                    (highlightedAnswerId != null &&
                        highlightedAnswerId.isNotEmpty &&
                        answer.id == highlightedAnswerId),
              )
              .toList(),
        ).asBroadcastStream()
      : null;
  if (!context.mounted) {
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('質問コメント')),
        body: SafeArea(
          child: LessonQuestionsPanel(
            course: _courseFromQuestion(latestQuestion),
            lesson: CourseLesson(
              title: latestQuestion.lessonTitle,
              duration: '1分30秒',
            ),
            lessonNumber: latestQuestion.lessonNumber,
            initialSelectedQuestion: latestQuestion,
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
  String? overrideDisplayName,
  String? overrideBodyPreview,
}) {
  final displayName = _safeReplyTargetDisplayName(
    overrideDisplayName ?? answer.replyToDisplayName,
    role: answer.replyToAuthorRole,
  );
  final bodyPreview = hideBodyPreview ? null : overrideBodyPreview?.trim();
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

String _shortReplyPreview(String value) {
  final normalized = value.replaceAll('\n', ' ').trim();
  if (normalized.length <= 36) {
    return normalized;
  }
  return '${normalized.substring(0, 36)}...';
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
  if (!hasQuotedNoteAttachment(
    quotedNoteId: question.quotedNoteId,
    quotedNoteTitle: question.quotedNoteTitle,
    quotedNoteBody: question.quotedNoteBody,
  )) {
    return '引用メモはありません。';
  }
  final title = quotedNoteDisplayTitle(
    quotedNoteId: question.quotedNoteId,
    quotedNoteTitle: question.quotedNoteTitle,
  );
  final body = question.quotedNoteBody?.trim() ?? '';
  if (body.isEmpty) {
    return title;
  }
  if (title.isEmpty) {
    return body;
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
