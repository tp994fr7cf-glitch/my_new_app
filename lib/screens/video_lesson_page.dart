import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';

typedef QuizAnswerSaveOverride =
    Future<void> Function({
      required LessonEvent event,
      required int selectedChoiceIndex,
      required bool isCorrect,
    });

class VideoLessonPage extends StatefulWidget {
  const VideoLessonPage({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.onQuizAnswerSaveOverride,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final QuizAnswerSaveOverride? onQuizAnswerSaveOverride;

  @override
  State<VideoLessonPage> createState() => _VideoLessonPageState();
}

class _VideoLessonPageState extends State<VideoLessonPage> {
  static const int _developmentPlaybackDurationSec = 90;

  int _currentPositionSec = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  final Map<String, int> _selectedChoices = {};
  final Map<String, bool> _answerResults = {};
  String? _message;

  Course get course => widget.course;
  CourseLesson get lesson => widget.lesson;
  int get lessonNumber => widget.lessonNumber;

  bool get _isAudioLesson => lesson.mediaType == 'audio';
  int get _totalDurationSec => _developmentPlaybackDurationSec;
  bool get _isAtEnd => _currentPositionSec >= _totalDurationSec;
  IconData get _playButtonIcon {
    if (_isPlaying) {
      return Icons.pause;
    }
    if (_isAtEnd) {
      return Icons.replay;
    }
    return Icons.play_arrow;
  }

  String get _playButtonLabel {
    if (_isPlaying) {
      return '一時停止';
    }
    if (_isAtEnd) {
      return 'もう一度再生';
    }
    return '再生';
  }

  List<LessonEvent> get _dueQuizEvents {
    return course.lessonEvents
        .where((event) => event.lessonNumber == lessonNumber)
        .where((event) => event.isQuiz)
        .where((event) => event.timestampSec <= _currentPositionSec)
        .toList()
      ..sort((a, b) => a.timestampSec.compareTo(b.timestampSec));
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _pausePlayback();
      return;
    }

    if (_isAtEnd) {
      setState(() {
        _currentPositionSec = 0;
        _message = null;
      });
    }

    setState(() {
      _isPlaying = true;
      _message = null;
    });
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _playbackTimer?.cancel();
        return;
      }

      setState(() {
        if (_currentPositionSec < _totalDurationSec) {
          _currentPositionSec += 1;
        }
        if (_currentPositionSec >= _totalDurationSec) {
          _currentPositionSec = _totalDurationSec;
          _isPlaying = false;
          _playbackTimer?.cancel();
        }
      });
    });
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _advanceTime() {
    setState(() {
      _currentPositionSec = (_currentPositionSec + 30)
          .clamp(0, _totalDurationSec)
          .toInt();
      if (_isAtEnd) {
        _isPlaying = false;
        _playbackTimer?.cancel();
      }
      _message = null;
    });
  }

  Future<void> _submitAnswer(LessonEvent event) async {
    final selectedChoiceIndex = _selectedChoices[event.id];
    final quiz = event.quiz;
    if (selectedChoiceIndex == null || quiz == null) {
      setState(() {
        _message = '回答を選択してください。';
      });
      return;
    }

    final isCorrect = selectedChoiceIndex == quiz.correctChoiceIndex;

    try {
      final saveOverride = widget.onQuizAnswerSaveOverride;
      if (saveOverride != null) {
        await saveOverride(
          event: event,
          selectedChoiceIndex: selectedChoiceIndex,
          isCorrect: isCorrect,
        );
      } else {
        await _saveQuizAnswer(
          event: event,
          selectedChoiceIndex: selectedChoiceIndex,
          isCorrect: isCorrect,
        );
      }

      if (mounted) {
        setState(() {
          _answerResults[event.id] = isCorrect;
          _message = isCorrect ? '正解です。' : '不正解です。解説を確認しましょう。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '回答の保存に失敗しました。後でもう一度お試しください。';
        });
      }
    }
  }

  Future<void> _saveQuizAnswer({
    required LessonEvent event,
    required int selectedChoiceIndex,
    required bool isCorrect,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final quiz = event.quiz;
    if (quiz == null) {
      return;
    }

    final courseId = course.id ?? course.title.replaceAll('/', '_');
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('quizAttempts')
        .add({
          'userId': user.uid,
          'courseId': courseId,
          'courseTitle': course.title,
          'lessonNumber': lessonNumber,
          'lessonTitle': lesson.title,
          'eventId': event.id,
          'question': quiz.question,
          'selectedChoiceIndex': selectedChoiceIndex,
          'correctChoiceIndex': quiz.correctChoiceIndex,
          'isCorrect': isCorrect,
          'answeredAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isAudioLesson ? '音声授業' : '動画視聴')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 260),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isAudioLesson ? Icons.headphones : Icons.smart_display,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(_isAudioLesson ? '音声プレイヤー仮UI' : '動画プレイヤー仮UI'),
                    const SizedBox(height: 4),
                    Text(
                      _isAudioLesson
                          ? '実際の音声再生機能は後で追加します。'
                          : '実際の動画再生機能は後で追加します。',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${_formatTime(_currentPositionSec)} / ${_formatTime(_totalDurationSec)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: LinearProgressIndicator(
                        value: _totalDurationSec == 0
                            ? 0
                            : _currentPositionSec / _totalDurationSec,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _togglePlayback,
                      icon: Icon(_playButtonIcon),
                      label: Text(_playButtonLabel),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(course.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'レッスン$lessonNumber: ${lesson.title}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('再生時間: ${lesson.duration}'),
            const SizedBox(height: 8),
            Text('授業形式: ${_isAudioLesson ? '音声のみ' : '動画'}'),
            const SizedBox(height: 8),
            Text('仮再生時間: ${_formatTime(_totalDurationSec)}'),
            const SizedBox(height: 8),
            Text('現在位置: ${_formatTime(_currentPositionSec)}'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _advanceTime,
              icon: const Icon(Icons.forward_30),
              label: const Text('30秒進める（開発用）'),
            ),
            if (lesson.mediaUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('仮URL: ${lesson.mediaUrl}'),
            ],
            if (_dueQuizEvents.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionTitle('授業中クイズ'),
              const SizedBox(height: 8),
              for (final event in _dueQuizEvents) ...[
                _QuizCard(
                  event: event,
                  selectedChoiceIndex: _selectedChoices[event.id],
                  answerResult: _answerResults[event.id],
                  onChoiceChanged: (choiceIndex) {
                    setState(() {
                      _selectedChoices[event.id] = choiceIndex;
                      _message = null;
                    });
                  },
                  onSubmit: () => _submitAnswer(event),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle('学習メモ'),
            const SizedBox(height: 8),
            const TextField(
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'このレッスンで気づいたことをメモできます。保存機能は後で追加します。',
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('この画面に後で追加する機能'),
            const SizedBox(height: 8),
            _BulletText(_isAudioLesson ? '実際の音声プレイヤー' : '実際の動画プレイヤー'),
            const _BulletText('再生位置の保存'),
            const _BulletText('視聴完了チェック'),
            const _BulletText('コメント・質問欄'),
          ],
        ),
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.event,
    required this.selectedChoiceIndex,
    required this.answerResult,
    required this.onChoiceChanged,
    required this.onSubmit,
  });

  final LessonEvent event;
  final int? selectedChoiceIndex;
  final bool? answerResult;
  final ValueChanged<int> onChoiceChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final quiz = event.quiz!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${event.timestampSec}秒のクイズ'),
            const SizedBox(height: 8),
            Text(
              quiz.question,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final entry in quiz.choices.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selectedChoiceIndex == entry.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(entry.$2),
                onTap: () => onChoiceChanged(entry.$1),
              ),
            FilledButton(onPressed: onSubmit, child: const Text('回答する')),
            if (answerResult != null) ...[
              const SizedBox(height: 8),
              Text(answerResult! ? '結果: 正解' : '結果: 不正解'),
              if (quiz.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('解説: ${quiz.explanation}'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
