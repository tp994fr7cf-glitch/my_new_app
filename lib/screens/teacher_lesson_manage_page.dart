import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/lesson_media_storage_service.dart';
import 'teacher_quiz_manage_page.dart';

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
  static const _mediaStorageService = LessonMediaStorageService();

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
              ? '1分30秒'
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

  Future<void> _uploadLessonMedia({
    required int lessonNumber,
    required _LessonEditorState editor,
  }) async {
    final courseId = widget.course.id;
    if (courseId == null) {
      setState(() {
        _message = '講座IDがないためアップロードできません。';
      });
      return;
    }

    setState(() {
      editor.isUploading = true;
      editor.uploadProgress = 0;
      _message = null;
    });

    try {
      final result = await _mediaStorageService.pickAndUploadLessonMedia(
        courseId: courseId,
        lessonNumber: lessonNumber,
        mediaType: editor.mediaType,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            editor.uploadProgress = progress;
          });
        },
      );
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() {
          editor.isUploading = false;
          editor.uploadProgress = null;
        });
        return;
      }

      editor.mediaUrlController.text = result.downloadUrl;
      setState(() {
        editor.isUploading = false;
        editor.uploadProgress = null;
        _message =
            'レッスン$lessonNumber の${_mediaStorageService.mediaTypeLabel(editor.mediaType)}をアップロードしました。'
            '「レッスン情報を保存」を押して反映してください。';
      });
    } on LessonMediaStorageException catch (error) {
      if (mounted) {
        setState(() {
          editor.isUploading = false;
          editor.uploadProgress = null;
          _message = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          editor.isUploading = false;
          editor.uploadProgress = null;
          _message = 'アップロードに失敗しました: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseId = widget.course.id;
    final canUploadMedia = courseId != null && courseId.isNotEmpty;

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
            const Text(
              '音声・動画ファイルは Firebase Storage にアップロードできます。'
              'アップロード後は「レッスン情報を保存」を押してください。',
            ),
            if (!canUploadMedia) ...[
              const SizedBox(height: 8),
              Text(
                '講座IDがないため、この画面ではアップロードできません。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            for (final entry in _lessonEditors.indexed) ...[
              _LessonEditorCard(
                index: entry.$1 + 1,
                course: widget.course,
                editor: entry.$2,
                canUploadMedia: canUploadMedia,
                requiredText: _requiredText,
                onChanged: () => setState(() {}),
                onUpload: () => _uploadLessonMedia(
                  lessonNumber: entry.$1 + 1,
                  editor: entry.$2,
                ),
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
    this.isUploading = false,
    this.uploadProgress,
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
  bool isUploading;
  double? uploadProgress;

  void dispose() {
    titleController.dispose();
    durationController.dispose();
    mediaUrlController.dispose();
  }
}

class _LessonEditorCard extends StatelessWidget {
  const _LessonEditorCard({
    required this.index,
    required this.course,
    required this.editor,
    required this.canUploadMedia,
    required this.requiredText,
    required this.onChanged,
    required this.onUpload,
  });

  final int index;
  final Course course;
  final _LessonEditorState editor;
  final bool canUploadMedia;
  final String? Function(String? value) requiredText;
  final VoidCallback onChanged;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    const mediaStorageService = LessonMediaStorageService();
    final mediaLabel = mediaStorageService.mediaTypeLabel(editor.mediaType);
    final allowedExtensions = mediaStorageService.allowedExtensionsForMediaType(
      editor.mediaType,
    );
    final hasMediaUrl = editor.mediaUrlController.text.trim().isNotEmpty;

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
                hintText: '例: 1分30秒',
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
              onChanged: editor.isUploading
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      editor.mediaType = value;
                      onChanged();
                    },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: !canUploadMedia || editor.isUploading ? null : onUpload,
              icon: Icon(
                editor.mediaType == 'audio'
                    ? Icons.upload_file
                    : Icons.video_file_outlined,
              ),
              label: Text('$mediaLabelファイルをアップロード'),
            ),
            const SizedBox(height: 8),
            Text(
              '対応形式: ${allowedExtensions.join(' / ')}（50MBまで）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (editor.isUploading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: editor.uploadProgress == null
                    ? null
                    : editor.uploadProgress!.clamp(0, 1),
              ),
              const SizedBox(height: 8),
              Text('アップロード中… ${((editor.uploadProgress ?? 0) * 100).round()}%'),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.mediaUrlController,
              readOnly: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '$mediaLabel URL',
                hintText: 'アップロード後に自動入力されます',
                suffixIcon: hasMediaUrl
                    ? const Icon(Icons.check_circle_outline)
                    : null,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('無料プレビュー'),
              value: editor.isPreview,
              onChanged: editor.isUploading
                  ? null
                  : (value) {
                      editor.isPreview = value;
                      onChanged();
                    },
            ),
            OutlinedButton.icon(
              onPressed: editor.isUploading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeacherQuizManagePage(
                            course: course,
                            lessonNumber: index,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.quiz),
              label: const Text('クイズを管理'),
            ),
          ],
        ),
      ),
    );
  }
}
