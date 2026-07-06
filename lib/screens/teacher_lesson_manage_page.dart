import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_duration_parser.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_whiteboard.dart';
import '../services/lesson_media_duration_service.dart';
import '../services/lesson_media_storage_service.dart';
import '../widgets/lesson_whiteboard_editor_panel.dart';
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
  static const _durationService = LessonMediaDurationService();

  late List<_LessonEditorState> _lessonEditors;
  late Course _activeCourse;
  bool _isSaving = false;
  bool _isLoadingLessons = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _activeCourse = widget.course;
    _lessonEditors = _activeCourse.lessons
        .map(_LessonEditorState.fromLesson)
        .toList();
    unawaited(_loadLatestLessons());
  }

  @override
  void dispose() {
    for (final editor in _lessonEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLatestLessons() async {
    final courseId = widget.course.id;
    if (courseId == null || widget.onSaveOverride != null) {
      return;
    }

    setState(() {
      _isLoadingLessons = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .get();
      if (!mounted || !snapshot.exists) {
        return;
      }

      final latestCourse = Course.fromFirestore(snapshot);
      setState(() {
        _activeCourse = latestCourse;
        for (final editor in _lessonEditors) {
          editor.dispose();
        }
        _lessonEditors = latestCourse.lessons
            .map(_LessonEditorState.fromLesson)
            .toList();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '保存済みレッスン情報の読み込みに失敗しました。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLessons = false;
        });
      }
    }
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

      final durationLabel = editor.durationController.text.trim().isEmpty
          ? '1分30秒'
          : editor.durationController.text.trim();
      final mediaDurationSec = editor.mediaDurationSec > 0
          ? editor.mediaDurationSec
          : (parseLessonDurationLabel(durationLabel) ?? 0);

      lessons.add(
        CourseLesson(
          title: title,
          duration: durationLabel,
          mediaType: editor.mediaType,
          mediaUrl: editor.mediaUrlController.text.trim(),
          mediaDurationSec: mediaDurationSec,
          isPreview: editor.isPreview,
          whiteboard: resolveWhiteboardForLessonPublish(
            publishedWhiteboard: editor.publishedWhiteboard,
            draftWhiteboard: editor.draftWhiteboard,
            workingWhiteboard: editor.workingWhiteboard,
          ),
          whiteboardDraft: null,
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
          for (var index = 0; index < _lessonEditors.length; index++) {
            if (index >= lessons.length) {
              continue;
            }
            final editor = _lessonEditors[index];
            final savedLesson = lessons[index];
            editor.publishedWhiteboard = savedLesson.whiteboard;
            editor.draftWhiteboard = null;
            editor.workingWhiteboard = savedLesson.whiteboard ?? const LessonWhiteboard();
          }
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

    final shouldPick = await _showUploadGuideDialog(
      mediaType: editor.mediaType,
    );
    if (!shouldPick || !mounted) {
      return;
    }

    setState(() {
      _message = null;
    });

    PlatformFile? pickedFile;
    try {
      pickedFile = await _mediaStorageService.pickLessonMediaFile(
        mediaType: editor.mediaType,
      );
    } on LessonMediaStorageException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
      return;
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'ファイル選択に失敗しました: $error';
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    if (pickedFile == null) {
      setState(() {
        _message = 'ファイル選択をキャンセルしました。';
      });
      return;
    }

    setState(() {
      editor.isUploading = true;
      editor.uploadProgress = 0;
      _message = null;
    });

    try {
      final result = await _mediaStorageService.uploadLessonMediaFile(
        courseId: courseId,
        lessonNumber: lessonNumber,
        mediaType: editor.mediaType,
        pickedFile: pickedFile,
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

      final detectedDurationSec = await _durationService.detectDurationSec(
        pickedFile,
      );

      editor.mediaUrlController.text = result.downloadUrl;
      if (detectedDurationSec != null && detectedDurationSec > 0) {
        editor.mediaDurationSec = detectedDurationSec;
      }
      setState(() {
        editor.isUploading = false;
        editor.uploadProgress = null;
        _message =
            'レッスン$lessonNumber の${_mediaStorageService.mediaTypeLabel(editor.mediaType)}をアップロードしました。'
            '${detectedDurationSec != null ? '（再生時間: ${detectedDurationSec}秒）' : ''}'
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

  Future<bool> _showUploadGuideDialog({required String mediaType}) async {
    final mediaLabel = _mediaStorageService.mediaTypeLabel(mediaType);
    final allowedExtensions = _mediaStorageService.allowedExtensionsForMediaType(
      mediaType,
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('$mediaLabelファイルを選びます'),
          content: SingleChildScrollView(
            child: Text(
              '端末内の$mediaLabelファイルを選んでアップロードします。\n\n'
              '【エミュレータの場合】\n'
              '最初は「まだ一つも項目がありません」と出ることがあります。\n'
              'その場合は、先に PC から音声ファイルを Download フォルダへ入れてください。\n\n'
              '1. 画面の ≡（メニュー）または「ダウンロード」を開く\n'
              '2. test.mp3 などを選ぶ\n'
              '3. 戻るときは端末画面下の ◁（戻る）ボタン\n\n'
              '【対応形式】\n'
              '${allowedExtensions.join(' / ')}（50MBまで）',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ファイルを選ぶ'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _saveWhiteboardDraft({
    required int lessonIndex,
    required _LessonEditorState editor,
    required LessonWhiteboard whiteboard,
  }) async {
    final courseId = widget.course.id;
    if (courseId == null) {
      throw StateError('講座IDがないため一時保存できません。');
    }

    await saveLessonWhiteboardDraft(
      courseId: courseId,
      lessonIndex: lessonIndex,
      whiteboard: whiteboard,
    );

    if (mounted) {
      setState(() {
        editor.draftWhiteboard = whiteboard.isEmpty ? null : whiteboard;
        editor.workingWhiteboard = whiteboard;
      });
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
              'アップロード後は「レッスン情報を保存」を押してください。'
              'エミュレータでは、先に PC から音声ファイルを Download フォルダへ入れる必要があります。',
            ),
            if (!canUploadMedia) ...[
              const SizedBox(height: 8),
              Text(
                '講座IDがないため、この画面ではアップロードできません。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (_isLoadingLessons) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            for (final entry in _lessonEditors.indexed) ...[
              _LessonEditorCard(
                index: entry.$1 + 1,
                lessonIndex: entry.$1,
                course: _activeCourse,
                editor: entry.$2,
                canUploadMedia: canUploadMedia,
                requiredText: _requiredText,
                onChanged: () => setState(() {}),
                onUpload: () => _uploadLessonMedia(
                  lessonNumber: entry.$1 + 1,
                  editor: entry.$2,
                ),
                onDraftSaved: (whiteboard) => _saveWhiteboardDraft(
                  lessonIndex: entry.$1,
                  editor: entry.$2,
                  whiteboard: whiteboard,
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
    this.mediaDurationSec = 0,
    this.isUploading = false,
    this.uploadProgress,
    this.publishedWhiteboard,
    this.draftWhiteboard,
    LessonWhiteboard? workingWhiteboard,
  }) : workingWhiteboard = workingWhiteboard ?? const LessonWhiteboard();

  factory _LessonEditorState.fromLesson(CourseLesson lesson) {
    final merged = mergeWhiteboardDraft(
      published: lesson.whiteboard,
      draft: lesson.whiteboardDraft,
    );

    return _LessonEditorState(
      titleController: TextEditingController(text: lesson.title),
      durationController: TextEditingController(text: lesson.duration),
      mediaUrlController: TextEditingController(text: lesson.mediaUrl),
      mediaType: lesson.mediaType == 'audio' ? 'audio' : 'video',
      isPreview: lesson.isPreview,
      mediaDurationSec: lesson.mediaDurationSec,
      publishedWhiteboard: lesson.whiteboard,
      draftWhiteboard: lesson.whiteboardDraft,
      workingWhiteboard: merged,
    );
  }

  final TextEditingController titleController;
  final TextEditingController durationController;
  final TextEditingController mediaUrlController;
  String mediaType;
  bool isPreview;
  int mediaDurationSec;
  bool isUploading;
  double? uploadProgress;
  LessonWhiteboard? publishedWhiteboard;
  LessonWhiteboard? draftWhiteboard;
  LessonWhiteboard workingWhiteboard;

  void dispose() {
    titleController.dispose();
    durationController.dispose();
    mediaUrlController.dispose();
  }
}

class _LessonEditorCard extends StatelessWidget {
  const _LessonEditorCard({
    required this.index,
    required this.lessonIndex,
    required this.course,
    required this.editor,
    required this.canUploadMedia,
    required this.requiredText,
    required this.onChanged,
    required this.onUpload,
    required this.onDraftSaved,
  });

  final int index;
  final int lessonIndex;
  final Course course;
  final _LessonEditorState editor;
  final bool canUploadMedia;
  final String? Function(String? value) requiredText;
  final VoidCallback onChanged;
  final VoidCallback onUpload;
  final WhiteboardDraftSaveCallback onDraftSaved;

  @override
  Widget build(BuildContext context) {
    const mediaStorageService = LessonMediaStorageService();
    final mediaLabel = mediaStorageService.mediaTypeLabel(editor.mediaType);
    final allowedExtensions = mediaStorageService.allowedExtensionsForMediaType(
      editor.mediaType,
    );
    final hasMediaUrl = editor.mediaUrlController.text.trim().isNotEmpty;
    final isAudioLesson = editor.mediaType == 'audio';
    final courseId = course.id ?? '';
    final durationLabel = editor.durationController.text.trim().isEmpty
        ? '1分30秒'
        : editor.durationController.text.trim();

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
            if (isAudioLesson && hasMediaUrl && courseId.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              LessonWhiteboardEditorPanel(
                key: ValueKey('${courseId}_${index}_${editor.mediaUrlController.text}'),
                courseId: courseId,
                lessonNumber: index,
                mediaUrl: editor.mediaUrlController.text.trim(),
                mediaDurationSec: editor.mediaDurationSec,
                durationLabel: durationLabel,
                publishedWhiteboard: editor.publishedWhiteboard,
                draftWhiteboard: editor.draftWhiteboard,
                onDraftSaved: onDraftSaved,
                onWhiteboardChanged: (whiteboard) {
                  editor.workingWhiteboard = whiteboard;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
