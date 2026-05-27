import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class LearningRecordsPage extends StatefulWidget {
  const LearningRecordsPage({
    super.key,
    required this.user,
    this.learningEventsStream,
    this.quizAttemptsStream,
  });

  final User user;
  final Stream<List<Map<String, dynamic>>>? learningEventsStream;
  final Stream<List<Map<String, dynamic>>>? quizAttemptsStream;

  @override
  State<LearningRecordsPage> createState() => _LearningRecordsPageState();
}

enum _RecordType { views, quizzes, comments }

enum _PeriodFilter { all, today, sevenDays, thirtyDays }

class _LearningRecordsPageState extends State<LearningRecordsPage> {
  _RecordType _selectedType = _RecordType.views;
  _PeriodFilter _selectedPeriod = _PeriodFilter.all;

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
            const Text('視聴、クイズ回答、質問コメントの記録を切り替えて確認できます。'),
            const SizedBox(height: 24),
            _RecordTypeSelector(
              selectedType: _selectedType,
              onSelected: (type) {
                setState(() {
                  _selectedType = type;
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
            const SizedBox(height: 24),
            switch (_selectedType) {
              _RecordType.views => _ViewRecordsList(
                recordsStream: _learningEventsStream(),
                filterRecords: (records) =>
                    _filterByPeriod(records, 'createdAt'),
              ),
              _RecordType.quizzes => _QuizRecordsList(
                recordsStream: _quizAttemptsStream(),
                filterRecords: (records) =>
                    _filterByPeriod(records, 'answeredAt'),
              ),
              _RecordType.comments => const _FutureCommentsCard(),
            },
          ],
        ),
      ),
    );
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
          label: const Text('質問コメント'),
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

class _FutureCommentsCard extends StatelessWidget {
  const _FutureCommentsCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('質問コメント記録は、質問コメント機能の実装後にここへ表示します。'),
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
