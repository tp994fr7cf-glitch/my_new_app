import 'package:flutter/material.dart';

import '../models/course.dart';

class VideoLessonPage extends StatelessWidget {
  const VideoLessonPage({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;

  bool get _isAudioLesson => lesson.mediaType == 'audio';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isAudioLesson ? '音声授業' : '動画視聴')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isAudioLesson
                          ? Icons.headphones
                          : Icons.play_circle_fill,
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
            if (lesson.mediaUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('仮URL: ${lesson.mediaUrl}'),
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
